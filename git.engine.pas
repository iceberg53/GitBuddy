unit Git.Engine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, // DateUtils provides UnixToDateTime
  libgit2; // Consumes the flat libgit2-delphi API layer

type
  { Custom exception specifically for Git sub-system failures }
  EGitException = class(Exception);

  { Data record to simplify file status outputs to the frontend }
  TGitFileStatus = record
    Path: string;
    State: string;
    RawFlags: Cardinal;
  end;

  // A dynamic array type to pass lists of changed files cleanly
  TGitFileStatusArray = array of TGitFileStatus;

  TUnifiedNetworkPayload = record
    AuthData: git_credential_userpass_payload;
    LogOutput: TStrings;
  end;
  PUnifiedNetworkPayload = ^TUnifiedNetworkPayload;


  { Data record to simplify commit tracking details for the UI }
  TGitCommitDetails = record
    Id: string;        // The Commit SHA Hash string
    Message: string;   // The Commit Message summary
    Author: string;    // Author name string
    Email: string;     // Author email string
    Timestamp: TDateTime;
  end;

  TGitCommitHistoryArray = array of TGitCommitDetails;

  { The Object-Oriented Git Workspace Controller }
  TGitRepository = class
  private
    FHandle: Pgit_repository; // The actual C-pointer tracking our open repository
    FIsInitialized: Boolean;
    FDefaultAuthorName: string;
    FDefaultAuthorEmail: string;
    FGitToken: string;
    FAnsiUser: AnsiString;
    FAnsiToken: AnsiString;
    FAuthPayload: git_credential_userpass_payload;
    procedure CheckError(const ApiResult: Integer);
    procedure LoadUserIdentity;
  public
    constructor Open(const WorkspacePath: string);
    constructor Init(const WorkspacePath: string);
    constructor Clone(const URL, LocalPath, Username, Token: string; LogOutput: TStrings);

    destructor Destroy; override;

    function GetActiveBranchName: string;
    function GetStatus: TGitFileStatusArray;
    function GetCommitHistory: TGitCommitHistoryArray;
    function HasStagedChanges: Boolean;
    function GetFileDiff(const RelativeFilePath: string): string;
    function GetRemotesList: TStringList;
    function GetLocalBranchesList: TStringList;
    function IsRebasing: Boolean;
    procedure Push(const RemoteName, BranchName: string);
    procedure Pull(const RemoteName: string; LogOutput: TStrings);
    procedure RebaseContinue;
    procedure RebaseAbort;
    procedure RebaseBranch(const UpstreamBranchName: string);
    procedure MergeBranch(const SourceBranchName: string);
    procedure RenameBranch(const OldBranchName, NewBranchName: string);
    procedure StashSave(const StashMessage, OverrideName, OverrideEmail: string);
    procedure StashPop;
    procedure DeleteBranch(const BranchName: string);
    procedure CreateBranch(const NewBranchName: string);
    procedure SwitchToBranch(const BranchName: string);
    procedure Fetch(const RemoteName: string; LogOutput: TStrings);
    procedure DiscardChanges(const RelativeFilePath: string);
    procedure StageFile(const RelativeFilePath: string);
    procedure UnstageFile(const RelativeFilePath: string);
    procedure Commit(const CommitMessage, OverrideName, OverrideEmail: string);

    property GitToken: string read FGitToken write FGitToken;
    property DefaultAuthorName: string read FDefaultAuthorName;
    property DefaultAuthorEmail: string read FDefaultAuthorEmail;
    property Handle: Pgit_repository read FHandle;
  end;

implementation

// Standalone context helper used internally by the status callback thread
type
  PStatusCallbackPayload = ^TStatusCallbackPayload;
  TStatusCallbackPayload = record
    List: TGitFileStatusArray;
    Count: Integer;
  end;

// Internal matching signature mapping for the C callback engine
function InternalStatusCallback(path: PAnsiChar; status_flags: Cardinal; payload: Pointer): Integer; cdecl;
var
  Data: PStatusCallbackPayload;
  StateStr: string;
begin
  Data := PStatusCallbackPayload(payload);

  // Decode the bitmask flags down to human readable Pascal strings
  if (status_flags and GIT_STATUS_CONFLICTED) <> 0 then StateStr := '🔴 CONFLICT (Unmerged)'
  else if (status_flags and GIT_STATUS_WT_NEW) <> 0 then StateStr := 'Untracked'
  else if (status_flags and GIT_STATUS_WT_MODIFIED) <> 0 then StateStr := 'Modified'
  else if (status_flags and GIT_STATUS_WT_DELETED) <> 0 then StateStr := 'Deleted'
  else if (status_flags and GIT_STATUS_INDEX_NEW) <> 0 then StateStr := 'Staged (New)'
  else if (status_flags and GIT_STATUS_INDEX_MODIFIED) <> 0 then StateStr := 'Staged (Modified)'
  else Exit(0); // Safely skip pristine/clean repository files

  // Grow our safe Pascal dynamic array on the fly
  Inc(Data^.Count);
  SetLength(Data^.List, Data^.Count);

  Data^.List[Data^.Count - 1].Path := string(path);
  Data^.List[Data^.Count - 1].State := StateStr;
  Data^.List[Data^.Count - 1].RawFlags := status_flags;

  Result := 0; // 0 tells libgit2 to continue reading the directory tree
end;

// Internal function matching libgit2's network transfer progress signature
function InternalTransferProgressCallback(stats: Pgit_indexer_progress; payload: Pointer): Integer; cdecl;
var
  UnifiedPackage: PUnifiedNetworkPayload;
  LogStrings: TStrings;
  LogMessage: string;
  Percent: Double;
begin
  UnifiedPackage := PUnifiedNetworkPayload(payload);
  if not Assigned(UnifiedPackage) or not Assigned(UnifiedPackage^.LogOutput) then Exit(0);

  LogStrings := UnifiedPackage^.LogOutput;
  Percent := 0.0;

  // 1. Calculate the real-time completion percentage metrics
  if stats^.total_objects > 0 then
    Percent := (stats^.received_objects / stats^.total_objects) * 100.0;

  // 2. Format a highly professional terminal console logging string string
  LogMessage := Format('📡 Downloading objects: %d/%d (%d%%) | %d bytes received',
    [stats^.received_objects, stats^.total_objects, Trunc(Percent), stats^.received_bytes]);

  // Overwrite the last line in the ListBox so it updates smoothly without creating 10,000 lines of scrolling clutter
  if (LogStrings.Count > 0) and (Pos('📡 Downloading', LogStrings[LogStrings.Count - 1]) = 1) then
    LogStrings[LogStrings.Count - 1] := LogMessage
  else
    LogStrings.Add(LogMessage);

  // Force a native system thread context refresh switch so the UI paints the progress instantly
  CheckSynchronize(0);
  Result := 0;
end;


{ TGitRepository }

procedure TGitRepository.CheckError(const ApiResult: Integer);
var
  LastError: PGit_Error;
begin
  // Standardized error-trapping engine for all internal libgit2 interactions
  if ApiResult < 0 then
  begin
    LastError := git_error_last();
    if Assigned(LastError) then
      raise EGitException.Create('Git Error (' + IntToStr(ApiResult) + '): ' + string(LastError^.message))
    else
      raise EGitException.Create('Unhandled Git Subsystem Exception. Code: ' + IntToStr(ApiResult));
  end;
end;

procedure TGitRepository.LoadUserIdentity;
var
  ConfigHandle: Pgit_config;
  BufName, BufEmail: PAnsiChar;
begin
  // Set safe application-level defaults
  FDefaultAuthorName := 'GitBuddy Developer';
  FDefaultAuthorEmail := 'developer@gitbuddy.local';
  ConfigHandle := nil;

  // 1. Take a frozen snapshot of the repository configuration ecosystem.
  // This triggers the full escalation logic (Local > Global > System) natively!
  if git_repository_config_snapshot(@ConfigHandle, FHandle) = 0 then
  begin
    try
      // 2. Query the prioritized snapshot for the username string
      if git_config_get_string(@BufName, ConfigHandle, 'user.name') = 0 then
        FDefaultAuthorName := string(BufName);

      // 3. Query the prioritized snapshot for the email string
      if git_config_get_string(@BufEmail, ConfigHandle, 'user.email') = 0 then
        FDefaultAuthorEmail := string(BufEmail);

    finally
      // 4. Clean up the snapshot out of memory as demanded by the documentation comments
      git_config_free(ConfigHandle);
    end;
  end;
end;

constructor TGitRepository.Open(const WorkspacePath: string);
var
  LocalAnsiStr: AnsiString;
begin
  inherited Create;
  FHandle := nil;
  FIsInitialized := False;

  // 1. Force spin up the C engine
  CheckError(git_libgit2_init());
  FIsInitialized := True;

  // 2. Protect and transform the incoming Pascal string path safely
  LocalAnsiStr := AnsiString(WorkspacePath);

  // 3. Open handle securely
  CheckError(git_repository_open(@FHandle, PAnsiChar(LocalAnsiStr)));

  // 4. Load the user credentials into the object fields immediately upon opening!
  LoadUserIdentity;
end;

constructor TGitRepository.Init(const WorkspacePath: string);
var
  LocalPathAnsi: AnsiString;
begin
  inherited Create;
  FHandle := nil;
  FIsInitialized := False;

  CheckError(git_libgit2_init());
  FIsInitialized := True;

  LocalPathAnsi := AnsiString(WorkspacePath);
  // Initializes the directory structure and assigns
  // the live pointer directly to FHandle. The repository object is now ALIVE.
  CheckError(git_repository_init(@FHandle, PAnsiChar(LocalPathAnsi), 0));
  LoadUserIdentity;
end;

constructor TGitRepository.Clone(const URL, LocalPath, Username, Token: string; LogOutput: TStrings);
var
  CloneOpts: git_clone_options;
  LocalURL, LocalPathStr: AnsiString;
  NetworkPackage: TUnifiedNetworkPayload;
  LocalAnsiUser, LocalAnsiToken: AnsiString;
begin
  inherited Create;
  FHandle := nil;
  FIsInitialized := False;

  CheckError(git_libgit2_init());
  FIsInitialized := True;

  LocalURL := AnsiString(URL);
  LocalPathStr := AnsiString(LocalPath);

  CheckError(git_clone_options_init(@CloneOpts, 1));

  LocalAnsiUser := AnsiString(Username);
  if LocalAnsiUser = '' then LocalAnsiUser := 'git';
  LocalAnsiToken := AnsiString(Token);

  NetworkPackage.AuthData.username := PAnsiChar(LocalAnsiUser);
  NetworkPackage.AuthData.password := PAnsiChar(LocalAnsiToken);
  NetworkPackage.LogOutput := LogOutput;

  CloneOpts.fetch_opts.callbacks.credentials := @git_credential_userpass;
  CloneOpts.fetch_opts.callbacks.transfer_progress := @InternalTransferProgressCallback;
  CloneOpts.fetch_opts.callbacks.payload := @NetworkPackage;

  if Assigned(LogOutput) then
    LogOutput.Add('📡 Initializing secure object download mapping for clone target: ' + URL);

  // Downloads the cloud objects and assigns the live pointer directly to FHandle!
  CheckError(git_clone(@FHandle, PAnsiChar(LocalURL), PAnsiChar(LocalPathStr), @CloneOpts));

  // Cache the token to the instance field for future push/pull operations
  FGitToken := Token;
  LoadUserIdentity;
end;


destructor TGitRepository.Destroy;
begin
  // Clean up repository context handle automatically out of RAM
  if Assigned(FHandle) then
    git_repository_free(FHandle);

  // Safely spin down subsystem context counters
  if FIsInitialized then
    git_libgit2_shutdown();

  inherited Destroy;
end;

function TGitRepository.GetActiveBranchName: string;
var
  HeadRef: Pgit_reference;
  BranchName: PAnsiChar;
begin
  Result := '';
  HeadRef := nil;

  // Read head pointer safely
  if git_repository_head(@HeadRef, FHandle) = 0 then
  begin
    BranchName := git_reference_shorthand(HeadRef);
    Result := string(BranchName);
    git_reference_free(HeadRef); // Free reference memory immediately inside C layer
  end
  else
  begin
    // Check if git_repository_head_unborn returns true or read the reference shorthand directly
    if git_repository_head_unborn(FHandle) = 1 then
    begin
      // Pull the virtual path string out of the config
      // Alternate bulletproof check: ask libgit2 to resolve the reference name of the symbolic link
      if git_reference_dwim(@HeadRef, FHandle, 'HEAD') = 0 then
      begin
        try
          Result := string(git_reference_shorthand(HeadRef)); // Returns 'main' or 'master' flawlessly!
        finally
          git_reference_free(HeadRef);
        end;
      end;
    end;
  end;
  if Result = '' then Result := 'main'; // Ultimate structural fallback guard
end;

function TGitRepository.GetStatus: TGitFileStatusArray;
var
  PayloadContext: TStatusCallbackPayload;
begin
  PayloadContext.Count := 0;
  SetLength(PayloadContext.List, 0);

  // Feed our internal helper callback function directly to the dynamic loop
  CheckError(git_status_foreach(FHandle, @InternalStatusCallback, @PayloadContext));

  // Return the fully populated safe Pascal array back to the frontend
  Result := PayloadContext.List;
end;

function TGitRepository.GetCommitHistory: TGitCommitHistoryArray;
var
  Walker: Pgit_revwalk;
  CommitOid: git_oid;
  CommitObj: Pointer;
  AuthorSig: Pgit_signature;
  HistoryList: TGitCommitHistoryArray;
  Count: Integer;
  Buf: array[0..40] of Char;
begin
  Count := 0;
  HistoryList := nil;
  SetLength(HistoryList, 0);
  Walker := nil;

  // THE NEWBORN SHIELD: If the repository has zero commits, head is unborn.
  // We exit gracefully with our empty array rather than letting the walker throw a crash!
  if git_repository_head_unborn(FHandle) = 1 then
    Exit;

  if git_revwalk_new(@Walker, FHandle) = 0 then
  begin
    try
      git_revwalk_push_head(Walker);
      git_revwalk_sorting(Walker, GIT_SORT_TOPOLOGICAL or GIT_SORT_TIME);

      while git_revwalk_next(@CommitOid, Walker) = 0 do
      begin
        CommitObj := nil;
        if git_commit_lookup(@CommitObj, FHandle, @CommitOid) = 0 then
        begin
          try
            Inc(Count);
            SetLength(HistoryList, Count);

            git_oid_fmt(Buf, @CommitOid);
            Buf[40] := #0; // Explicitly null-terminate the buffer index

            HistoryList[Count - 1].Id := StrPas(Buf);
            HistoryList[Count - 1].Message := string(git_commit_message(CommitObj));

            AuthorSig := git_commit_author(CommitObj);
            if Assigned(AuthorSig) then
            begin
              // Mapping directly to the 'name_' and 'email' fields found in signature.inc!
              HistoryList[Count - 1].Author := string(AuthorSig^.name_);
              HistoryList[Count - 1].Email := string(AuthorSig^.email);
              HistoryList[Count - 1].Timestamp := UnixToDateTime(AuthorSig^.when.time);
            end;
          finally
            git_commit_free(CommitObj);
          end;
        end;
      end;
    finally
      git_revwalk_free(Walker);
    end;
  end;

  Result := HistoryList;
end;

procedure TGitRepository.StageFile(const RelativeFilePath: string);
var
  IndexHandle: Pgit_index;
  LocalPathStr: AnsiString;
begin
  IndexHandle := nil;
  CheckError(git_repository_index(@IndexHandle, FHandle));
  try
    LocalPathStr := AnsiString(RelativeFilePath);
    CheckError(git_index_add_bypath(IndexHandle, PAnsiChar(LocalPathStr)));
    CheckError(git_index_write(IndexHandle)); // Save index back to the disk filesystem
  finally
    git_index_free(IndexHandle);
  end;
end;

procedure TGitRepository.UnstageFile(const RelativeFilePath: string);
var
  IndexHandle: Pgit_index;
  HeadRef: Pgit_reference;
  HeadCommitObj: Pgit_object;
  LocalPathStr: AnsiString;
  PathsStrArray: git_strarray;
  PCharPath: PAnsiChar;
begin
  IndexHandle := nil;
  HeadRef := nil;
  HeadCommitObj := nil;

  CheckError(git_repository_index(@IndexHandle, FHandle));
  try
    LocalPathStr := AnsiString(RelativeFilePath);
    PCharPath := PAnsiChar(LocalPathStr);

    PathsStrArray.strings := @PCharPath;
    PathsStrArray.count := 1;

    if git_repository_head(@HeadRef, FHandle) = 0 then
    begin
      try
        if git_reference_peel(@HeadCommitObj, HeadRef, GIT_OBJECT_COMMIT) = 0 then
        begin
          CheckError(git_reset_default(FHandle, HeadCommitObj, @PathsStrArray));
          Exit;
        end;
      finally
        if Assigned(HeadCommitObj) then git_object_free(HeadCommitObj);
        if Assigned(HeadRef) then git_reference_free(HeadRef);
      end;
    end;

    CheckError(git_index_remove_bypath(IndexHandle, PAnsiChar(LocalPathStr)));
    CheckError(git_index_write(IndexHandle));

  finally
    git_index_free(IndexHandle);
  end;
end;


procedure TGitRepository.Commit(const CommitMessage, OverrideName, OverrideEmail: string);
var
  IndexHandle: Pgit_index;
  TreeOid: git_oid;
  TreeObj: Pgit_tree;
  ParentCount: Integer;
  HeadRef: Pgit_reference;
  HeadOid: git_oid;
  MergeHeadOid: git_oid;
  ParentsArray: array[0..1] of Pgit_commit; // FIXED: Can hold up to 2 parent commit nodes!
  Signature: Pgit_signature;
  NewCommitOid: git_oid;
  LocalMsg, LocalName, LocalEmail: AnsiString;
  I: Integer;
begin
  IndexHandle := nil;
  TreeObj := nil;
  HeadRef := nil;
  Signature := nil;
  ParentCount := 0;
  for I := 0 to 1 do ParentsArray[I] := nil;

  LocalMsg := AnsiString(CommitMessage);
  if Trim(OverrideName) <> '' then LocalName := AnsiString(OverrideName)
  else LocalName := AnsiString(FDefaultAuthorName);

  if Trim(OverrideEmail) <> '' then LocalEmail := AnsiString(OverrideEmail)
  else LocalEmail := AnsiString(FDefaultAuthorEmail);

  CheckError(git_repository_index(@IndexHandle, FHandle));
  try
    CheckError(git_index_write_tree(@TreeOid, IndexHandle));
    CheckError(git_tree_lookup(@TreeObj, FHandle, @TreeOid));

    // 1. RESOLVE PARENT 1: Read the current active local HEAD commit reference
    if git_repository_head(@HeadRef, FHandle) = 0 then
    begin
      if git_reference_name_to_id(@HeadOid, FHandle, git_reference_name(HeadRef)) = 0 then
      begin
        if git_commit_lookup(@ParentsArray[0], FHandle, @HeadOid) = 0 then
          ParentCount := 1;
      end;
    end;

    // 2. THE MERGE COMMIT FIX: Check if a merge transaction is currently open on disk
    // git_repository_message or checking for MERGE_HEAD provides this state tracking link natively
    if (git_repository_state(FHandle) = GIT_REPOSITORY_STATE_MERGE) then
    begin
      // Read the hidden secondary parent hash string directly out of the .git/MERGE_HEAD tracking file
      // Note: git_repository_mergehead_foreach loops through active merge heads. For a single merge, index 0 is fetched.
      // If your headers expose 'git_merge_head_lookup', you can substitute it here.
      // Alternate fallback: read the OID using the built-in library reference parser
      if git_reference_name_to_id(@MergeHeadOid, FHandle, 'MERGE_HEAD') = 0 then
      begin
        if git_commit_lookup(@ParentsArray[1], FHandle, @MergeHeadOid) = 0 then
          ParentCount := 2; // Mark that this commit has TWO parents (A True Merge Commit!)
      end;
    end;

    CheckError(git_signature_now(@Signature, PAnsiChar(LocalName), PAnsiChar(LocalEmail)));

    // 3. Create the commit using our updated parents array structure
    CheckError(git_commit_create(
      @NewCommitOid, FHandle, 'HEAD', Signature, Signature, nil,
      PAnsiChar(LocalMsg), TreeObj, ParentCount, @ParentsArray[0]
    ));

    // 4. CLEAN UP THE MERGE STATE: If this was a merge commit, wipe out the temporary MERGE_HEAD file system trackers
    if (ParentCount = 2) then
    begin
      git_repository_state_cleanup(FHandle); // 👈 Removes MERGE_HEAD and puts repo back to normal clean state!
    end;

  finally
    for I := 0 to 1 do
    begin
      if Assigned(ParentsArray[I]) then git_commit_free(ParentsArray[I]);
    end;
    if Assigned(Signature) then git_signature_free(Signature);
    if Assigned(TreeObj) then git_tree_free(TreeObj);
    if Assigned(HeadRef) then git_reference_free(HeadRef);
    git_index_free(IndexHandle);
  end;
end;

function TGitRepository.HasStagedChanges: Boolean;
var
  StatusList: TGitFileStatusArray;
  I: Integer;
begin
  Result := False;
  StatusList := GetStatus(); // Pull our existing status scanner array

  for I := 0 to High(StatusList) do
  begin
    // Check if the string status flag maps to any staging state
    if (Pos('Staged', StatusList[I].State) > 0) then
    begin
      Result := True;
      Exit; // Break early the moment we confirm at least one staged element
    end;
  end;
end;

procedure TGitRepository.DiscardChanges(const RelativeFilePath: string);
var
  Opts: git_checkout_options;
  LocalPathStr: AnsiString;
  PCharPath: PAnsiChar;
begin
  // 1. NATIVE INITIALIZATION: Sets up default states and internal structure values.
  // FPC traces this function call and instantly clears the "not initialized" Hint!
  CheckError(git_checkout_options_init(@Opts, 1)); // 1 corresponds to GIT_CHECKOUT_OPTIONS_VERSION

  // 2. Set the custom operational checkout strategy configurations
  Opts.checkout_strategy := GIT_CHECKOUT_FORCE or GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;

  // 3. Bind our path variable explicitly to the 'paths' attribute
  LocalPathStr := AnsiString(RelativeFilePath);
  PCharPath := PAnsiChar(LocalPathStr);

  Opts.paths.strings := @PCharPath;
  Opts.paths.count := 1;

  // 4. Execute the forced checkout operation down to disk
  CheckError(git_checkout_head(FHandle, @Opts));
end;

// Standalone callback required by libgit2 to process matching diff line chunks
function InternalDiffLineCallback(
  {%H-}diff_delta: Pgit_diff_delta; // {%H-} tells the Free Pascal compiler to ignore the unused hint
  {%H-}diff_hunk: Pgit_diff_hunk;   // {%H-} tells the Free Pascal compiler to ignore the unused hint
  diff_line: Pgit_diff_line;
  payload: Pointer): Integer; cdecl;
var
  OutputStringList: TStringList;
  LineText: string;
begin
  OutputStringList := TStringList(payload);

  LineText := ''; // Explicit assignment initializes the managed type cleanly

  // Isolate and capture the line text securely out of the raw C string buffer array
  SetLength(LineText, diff_line^.content_len);
  if diff_line^.content_len > 0 then
    Move(diff_line^.content^, Pointer(LineText)^, diff_line^.content_len); // Corrected pointer buffer cast

  // Prefix the text strings based on the Git modification origin signature marker
  case Char(diff_line^.origin) of
    '+': OutputStringList.Add('+' + LineText); // Injected line
    '-': OutputStringList.Add('-' + LineText); // Deleted line
    'H': OutputStringList.Add('@@ ' + Trim(LineText) + ' @@'); // Hunk coordinates separator
  else
    OutputStringList.Add(' ' + LineText); // Unmodified baseline context line
  end;

  Result := 0;
end;

function TGitRepository.GetFileDiff(const RelativeFilePath: string): string;
var
  DiffHandle: Pgit_diff; // Declared cleanly matching header structural expectations
  DiffOpts: git_diff_options;
  OutputList: TStringList;
  LocalPathStr: AnsiString;
  PCharPath: PAnsiChar;
  HeadRef: Pgit_reference;
  CommitObj: Pgit_commit;
  TreeObj: Pgit_tree;
begin
  Result := '';
  DiffHandle := nil;
  HeadRef := nil;
  CommitObj := nil;
  TreeObj := nil;

  // 1.
  CheckError(git_diff_options_init(@DiffOpts, GIT_DIFF_OPTIONS_VERSION));
  OutputList := TStringList.Create;

  LocalPathStr := AnsiString(RelativeFilePath);
  PCharPath := PAnsiChar(LocalPathStr);
  DiffOpts.pathspec.strings := @PCharPath;
  DiffOpts.pathspec.count := 1;

  try
    // 2. THE REBASE CONFLICT OVERRIDE:
    if IsRebasing and (git_repository_head(@HeadRef, FHandle) = 0) then
    begin
      try
        // Peel the detached head down to the underlying tree object context
        if (git_reference_peel(@CommitObj, HeadRef, GIT_OBJECT_COMMIT) = 0) and
           (git_commit_tree(@TreeObj, CommitObj) = 0) then
        begin
          // Perform native Tree-to-Workdir diffing bypassing the broken unmerged index database
          if git_diff_tree_to_workdir(@DiffHandle, FHandle, TreeObj, @DiffOpts) = 0 then
          begin
            git_diff_print(DiffHandle, GIT_DIFF_FORMAT_PATCH, @InternalDiffLineCallback, OutputList);
            Result := OutputList.Text;
          end;
        end;
      finally
        if Assigned(TreeObj) then git_tree_free(TreeObj);
        if Assigned(CommitObj) then git_commit_free(CommitObj);
        if Assigned(HeadRef) then git_reference_free(HeadRef);
      end;
    end;

    // 3. STANDARD FALLBACK: If the repo isn't rebasing, fall back to our index tracker
    if (DiffHandle = nil) then
    begin
      if git_diff_index_to_workdir(@DiffHandle, FHandle, nil, @DiffOpts) = 0 then
      begin
        git_diff_print(DiffHandle, GIT_DIFF_FORMAT_PATCH, @InternalDiffLineCallback, OutputList);
        Result := OutputList.Text;
      end;
    end;

  finally
    if Assigned(DiffHandle) then git_diff_free(DiffHandle);
    OutputList.Free;
  end;
end;


function TGitRepository.GetRemotesList: TStringList;
var
  RemoteArr: git_strarray;
  I: Integer;
begin
  Result := TStringList.Create;

  // 👈 THE NATIVE Pascal FIX: Directly assign default values.
  // This satisfies the strict compiler tracker natively, erasing the Hint!
  RemoteArr.strings := nil;
  RemoteArr.count := 0;

  // 1. Ask libgit2 to query the repository configuration for all configured remote names
  if git_remote_list(@RemoteArr, FHandle) = 0 then
  begin
    try
      // 2. Loop through the raw C string array and append them into our clean Pascal list
      for I := 0 to RemoteArr.count - 1 do
      begin
        Result.Add(string(RemoteArr.strings[I]));
      end;
    finally
      git_strarray_dispose(@RemoteArr); // Always free C string array structures cleanly
    end;
  end;

  if Result.Count = 0 then
    Result.Add('origin');
end;

procedure TGitRepository.Fetch(const RemoteName: string; LogOutput: TStrings);
var
  RemoteHandle: Pgit_remote;
  FetchOpts: git_fetch_options;
  LocalRemoteName: AnsiString;
  ReflogMsg: AnsiString;
  NetworkPackage: TUnifiedNetworkPayload; // 👈 OUR COMBINED DATA CONSTRUCTOR PASSENGER
begin
  RemoteHandle := nil;
  LocalRemoteName := AnsiString(RemoteName);

  CheckError(git_remote_lookup(@RemoteHandle, FHandle, PAnsiChar(LocalRemoteName)));
  try
    CheckError(git_fetch_options_init(@FetchOpts, GIT_FETCH_OPTIONS_VERSION));

    // 1. Pack our credentials data matching your profile setups
    FAnsiUser := AnsiString(FDefaultAuthorName);
    FAnsiToken := AnsiString(FGitToken);
    NetworkPackage.AuthData.username := PAnsiChar(FAnsiUser);
    NetworkPackage.AuthData.password := PAnsiChar(FAnsiToken);

    // 2. Pack our UI console logging destination handle
    NetworkPackage.LogOutput := LogOutput;

    // 3. Link your authentication routine to the stock handler
    FetchOpts.callbacks.credentials := @git_credential_userpass;

    // 4. Link your dynamic scrolling text renderer callback
    FetchOpts.callbacks.transfer_progress := @InternalTransferProgressCallback;

    // 5. 👈 THE MASTER INTEGRATION LINK: Pass the single address of our combined package structure!
    // Both callbacks will now read from their respective parts of this stable shared memory cell.
    FetchOpts.callbacks.payload := @NetworkPackage;

    if Assigned(LogOutput) then
      LogOutput.Add('📡 Initializing secure internet sockets connecting to: ' + RemoteName);

    ReflogMsg := AnsiString('Fetch from client UI dashboard');
    CheckError(git_remote_fetch(RemoteHandle, nil, @FetchOpts, PAnsiChar(ReflogMsg)));

    if Assigned(LogOutput) then
      LogOutput.Add('🎉 Synchronization complete!');
  finally
    if Assigned(RemoteHandle) then
      git_remote_free(RemoteHandle);
  end;
end;

function TGitRepository.GetLocalBranchesList: TStringList;
var
  IteratorHandle: Pgit_branch_iterator;
  RefHandle: Pgit_reference;
  BranchType: Cardinal; // Holds GIT_BRANCH_LOCAL or GIT_BRANCH_REMOTE
  BranchName: PAnsiChar;
begin
  Result := TStringList.Create;
  IteratorHandle := nil;
  RefHandle := nil;

  // 1. Create a branch iterator restricted strictly to local branches (GIT_BRANCH_LOCAL = 1)
  if git_branch_iterator_new(@IteratorHandle, FHandle, 1) = 0 then
  begin
    try
      // 2. Loop through references until the iterator returns GIT_ITEROVER (usually a negative termination code)
      while git_branch_next(@RefHandle, @BranchType, IteratorHandle) = 0 do
      begin
        try
          // 3. Extract the clean short name of the branch reference
          if git_branch_name(@BranchName, RefHandle) = 0 then
          begin
            Result.Add(string(BranchName));
          end;
        finally
          git_reference_free(RefHandle); // Free specific reference handle context inside loop iterations
        end;
      end;
    finally
      git_branch_iterator_free(IteratorHandle); // Clean the iterator architecture footprint out of memory
    end;
  end;

  // Fallback safety if the list is completely blank
  if Result.Count = 0 then
    Result.Add('main');
end;

procedure TGitRepository.SwitchToBranch(const BranchName: string);
var
  BranchRef: Pgit_reference;
  TargetObj: Pgit_object;
  CheckoutOpts: git_checkout_options;
  LocalBranchName: AnsiString;
begin
  BranchRef := nil;
  TargetObj := nil;
  LocalBranchName := AnsiString(BranchName);

  // 1. Look up the local branch reference pointer using its short name (GIT_BRANCH_LOCAL = 1)
  CheckError(git_branch_lookup(@BranchRef, FHandle, PAnsiChar(LocalBranchName), 1));
  try
    // 2. Resolve (peel) the branch reference down to its underlying target commit object
    CheckError(git_reference_peel(@TargetObj, BranchRef, GIT_OBJECT_COMMIT));
    try
      // 3. Initialize the native checkout options to safely overwrite your working directory files
      CheckError(git_checkout_options_init(@CheckoutOpts, 1));
      CheckoutOpts.checkout_strategy := GIT_CHECKOUT_SAFE; // Prevents overwriting local unsaved changes

      // 4. Update the physical files on your hard disk to match the selected branch target commit tree
      CheckError(git_checkout_tree(FHandle, TargetObj, @CheckoutOpts));

      // 5. Move the master HEAD tracking pointer to point to the new branch reference name
      CheckError(git_repository_set_head(FHandle, git_reference_name(BranchRef)));
    finally
      if Assigned(TargetObj) then git_object_free(TargetObj);
    end;
  finally
    if Assigned(BranchRef) then git_reference_free(BranchRef);
  end;
end;

procedure TGitRepository.CreateBranch(const NewBranchName: string);
var
  HeadRef: Pgit_reference;
  TargetCommitObj: Pgit_object;
  NewBranchRef: Pgit_reference;
  LocalBranchName: AnsiString;
begin
  HeadRef := nil;
  TargetCommitObj := nil;
  NewBranchRef := nil;
  LocalBranchName := AnsiString(NewBranchName);

  // 1. Query the repository to fetch the active HEAD reference
  if git_repository_head(@HeadRef, FHandle) <> 0 then
    raise EGitException.Create('Cannot create branch: Repository has no historical HEAD commit reference yet.');

  try
    // 2. Resolve (peel) the HEAD reference down to its underlying target commit object context
    CheckError(git_reference_peel(@TargetCommitObj, HeadRef, GIT_OBJECT_COMMIT));
    try
      // 3. Fire the native libgit2 branch creation engine
      // Parameter 1: Destination pointer tracker to receive the new branch reference
      // Parameter 2: Active repository pointer handle
      // Parameter 3: Name string for the new line
      // Parameter 4: Target commit object block to attach the new line to
      // Parameter 5: Force overwrite flag (0 = false, do not overwrite if name already exists)
      CheckError(git_branch_create(@NewBranchRef, FHandle, PAnsiChar(LocalBranchName), Pgit_commit(TargetCommitObj), 0));
    finally
      if Assigned(NewBranchRef) then git_reference_free(NewBranchRef);
    end;
  finally
    if Assigned(TargetCommitObj) then git_object_free(TargetCommitObj);
    if Assigned(HeadRef) then git_reference_free(HeadRef);
  end;
end;

procedure TGitRepository.DeleteBranch(const BranchName: string);
var
  BranchRef: Pgit_reference;
  LocalBranchName: AnsiString;
begin
  BranchRef := nil;
  LocalBranchName := AnsiString(BranchName);

  // 1. Safety Rule: Proactively block the user if they try to pass their currently active branch name
  if CompareText(BranchName, GetActiveBranchName) = 0 then
    raise EGitException.Create('Cannot delete branch "' + BranchName + '" because it is currently checked out.' + sLineBreak +
                               'Please switch to a different branch (like main) first.');

  // 2. Look up the targeted local branch reference handle (GIT_BRANCH_LOCAL = 1)
  CheckError(git_branch_lookup(@BranchRef, FHandle, PAnsiChar(LocalBranchName), 1));
  try
    // 3. Fire the native libgit2 structural branch deletion engine execution command
    CheckError(git_branch_delete(BranchRef));
  finally
    // Note: git_branch_delete frees the internal reference memory internally on success,
    // but wrapping it inside an assigned safety block safeguards against resource allocation leakage on failures.
    if Assigned(BranchRef) then
      git_reference_free(BranchRef);
  end;
end;

procedure TGitRepository.StashSave(const StashMessage, OverrideName, OverrideEmail: string);
var
  StashOid: git_oid;
  Signature: Pgit_signature;
  LocalMessage, LocalName, LocalEmail: AnsiString;
begin
  Signature := nil;
  LocalMessage := AnsiString(StashMessage);

  // LAST RESORT GUARD: Use the UI overrides if provided, else use discovered config
  if Trim(OverrideName) <> '' then LocalName := AnsiString(OverrideName)
  else LocalName := AnsiString(FDefaultAuthorName);

  if Trim(OverrideEmail) <> '' then LocalEmail := AnsiString(OverrideEmail)
  else LocalEmail := AnsiString(FDefaultAuthorEmail);

  // Sign the stash entry using your real native Git identity!
  CheckError(git_signature_now(@Signature, PAnsiChar(LocalName), PAnsiChar(LocalEmail)));
  try
    CheckError(git_stash_save(@StashOid, FHandle, Signature, PAnsiChar(LocalMessage), 0));
  finally
    if Assigned(Signature) then
      git_signature_free(Signature);
  end;
end;

procedure TGitRepository.StashPop;
var
  PopOpts: git_stash_apply_options;
begin
  // 1. NATIVE INITIALIZATION: This initializes PopOpts and all its nested
  // sub-structures (like checkout_options) to their legal default values!
  // FPC traces this and immediately clears the "not initialized" Hint.
  CheckError(git_stash_apply_options_init(@PopOpts, 1)); // 1 corresponds to GIT_STASH_APPLY_OPTIONS_VERSION

  // 2. OPTIONAL UX REINFORCEMENT: Explicitly ensure the nested checkout strategy
  // uses safe workstation safeguards (GIT_CHECKOUT_SAFE = 1).
  PopOpts.checkout_options.checkout_strategy := 1;

  // 3. Execute the popping stream passing our pristine, natively-configured structure pointer
  CheckError(git_stash_pop(FHandle, 0, @PopOpts));
end;

procedure TGitRepository.RenameBranch(const OldBranchName, NewBranchName: string);
var
  BranchRef: Pgit_reference;
  NewBranchRef: Pgit_reference;
  LocalNewName: AnsiString;
  LocalOldName: AnsiString;
begin
  BranchRef := nil;
  NewBranchRef := nil;
  LocalOldName := AnsiString(OldBranchName);
  LocalNewName := AnsiString(NewBranchName);

  // 1. Look up the existing local branch reference handle (GIT_BRANCH_LOCAL = 1)
  CheckError(git_branch_lookup(@BranchRef, FHandle, PAnsiChar(LocalOldName), GIT_BRANCH_LOCAL));
  try
    // 2. Fire the native libgit2 branch moving/renaming execution engine
    // Parameter 1: Destination out pointer to receive the updated reference structure
    // Parameter 2: Active source branch reference pointer to modify
    // Parameter 3: New name string for the line
    // Parameter 4: Force overwrite flag (0 = false, do not overwrite if name already exists)
    CheckError(git_branch_move(@NewBranchRef, BranchRef, PAnsiChar(LocalNewName), 0));

    if Assigned(NewBranchRef) then
      git_reference_free(NewBranchRef);
  finally
    if Assigned(BranchRef) then
      git_reference_free(BranchRef);
  end;
end;

procedure TGitRepository.MergeBranch(const SourceBranchName: string);
var
  BranchRef: Pgit_reference;
  AnnotatedHead: Pgit_annotated_commit;
  HeadsArray: array[0..0] of Pgit_annotated_commit;
  MergeOpts: git_merge_options;
  CheckoutOpts: git_checkout_options;
  LocalSourceName: AnsiString;
begin
  BranchRef := nil;
  AnnotatedHead := nil;
  LocalSourceName := AnsiString(SourceBranchName);

  // 1. THE PULL MERGE FIX: Use generic reference lookup instead of strict branch lookup!
  // This allows the engine to locate any system reference layer (local, remote tracking, or tags) natively.
  // If the passed string is a short name (like 'main'), we default attach the local head path qualifier.
  if (Pos('refs/', SourceBranchName) <> 1) then
    LocalSourceName := AnsiString('refs/heads/' + SourceBranchName);

  CheckError(git_reference_lookup(@BranchRef, FHandle, PAnsiChar(LocalSourceName)));
  try
    // 2. Wrap our found reference handle into an annotated commit structure
    CheckError(git_annotated_commit_from_ref(@AnnotatedHead, FHandle, BranchRef));
    try
      // 3. Initialize options structures natively via their internal blueprints
      CheckError(git_merge_options_init(@MergeOpts, 1));
      CheckError(git_checkout_options_init(@CheckoutOpts, 1));
      CheckoutOpts.checkout_strategy := 1; // GIT_CHECKOUT_SAFE

      // 4. Pack our single pointer node directly into the array block
      HeadsArray[0] := AnnotatedHead;

      // 5. Fire the merge engine passing the address of the array block
      CheckError(git_merge(FHandle, @HeadsArray, 1, @MergeOpts, @CheckoutOpts));

    finally
      if Assigned(AnnotatedHead) then
        git_annotated_commit_free(AnnotatedHead);
    end;
  finally
    if Assigned(BranchRef) then
      git_reference_free(BranchRef);
  end;
end;

procedure TGitRepository.RebaseBranch(const UpstreamBranchName: string);
var
  UpstreamRef: Pgit_reference;
  UpstreamHead: Pgit_annotated_commit;
  BranchHead: Pgit_annotated_commit;
  RebaseHandle: Pgit_rebase;
  RebaseOpts: git_rebase_options;
  CheckoutOpts: git_checkout_options;
  RebaseOp: Pgit_rebase_operation;
  LocalUpstreamName: AnsiString;
  LocalUpstreamCStr: PAnsiChar;
  ResultCode: Integer;
  NewCommitId: git_oid;
  Signature: Pgit_signature;
  ConflictEncountered: Boolean;
begin
  UpstreamRef := nil;
  UpstreamHead := nil;
  BranchHead := nil;
  RebaseHandle := nil;
  Signature := nil;
  ConflictEncountered := False;
  LocalUpstreamName := AnsiString(UpstreamBranchName);
  LocalUpstreamCStr := PAnsiChar(LocalUpstreamName);

  CheckError(git_branch_lookup(@UpstreamRef, FHandle, LocalUpstreamCStr, GIT_BRANCH_LOCAL));
  try
    CheckError(git_annotated_commit_from_ref(@UpstreamHead, FHandle, UpstreamRef));
    CheckError(git_annotated_commit_from_revspec(@BranchHead, FHandle, 'HEAD'));
    try
      CheckError(git_rebase_options_init(@RebaseOpts, 1));
      CheckError(git_checkout_options_init(@CheckoutOpts, 1));
      CheckoutOpts.checkout_strategy := 1; // GIT_CHECKOUT_SAFE
      RebaseOpts.checkout_options := CheckoutOpts;

      // Initialize the transaction stack state
      CheckError(git_rebase_init(@RebaseHandle, FHandle, nil, UpstreamHead, nil, @RebaseOpts));
      try
        CheckError(git_signature_now(@Signature, PAnsiChar(AnsiString(FDefaultAuthorName)), PAnsiChar(AnsiString(FDefaultAuthorEmail))));

        // Loop through the commits
        while git_rebase_next(@RebaseOp, RebaseHandle) = 0 do
        begin
          ResultCode := git_rebase_commit(@NewCommitId, RebaseHandle, nil, Signature, nil, nil);

          // 1. If a patch is already applied upstream (GIT_EAPPLIED = -18), skip it safely
          if ResultCode = GIT_EAPPLIED then
            Continue;

          // 2. If a patch introduces a conflict (GIT_EUNMERGED = -10), pause the transaction loop!
          if ResultCode = GIT_EUNMERGED then
          begin
            ConflictEncountered := True;
            Break; // Exit the loop immediately, leaving the rebase open and active
          end;

          // Handle generic hard failures
          if ResultCode <> GIT_OK then
            CheckError(ResultCode);
        end;

        // 3. If no conflicts were met, finalize the rebase completely
        if not ConflictEncountered then
        begin
          CheckError(git_rebase_finish(RebaseHandle, Signature));
        end
        else
        begin
          // Raise a custom warning telling the user that the rebase is paused for conflict resolution
          raise EGitException.Create('⚠️ Rebase Paused: Unmerged code conflicts were introduced by this patch.' + sLineBreak +
                                     'The conflicting files have been placed in your workspace.' + sLineBreak +
                                     'Please resolve the markers, stage the files, and commit to continue.');
        end;

      except
        on E: EGitException do
        begin
          // If it's our custom paused exception, don't abort! Pass it to the UI cleanly.
          if Pos('⚠️ Rebase Paused', E.Message) = 1 then raise;

          // For any other unexpected errors, abort and roll back
          if Assigned(RebaseHandle) then git_rebase_abort(RebaseHandle);
          raise;
        end;
        on E: Exception do
        begin
          if Assigned(RebaseHandle) then git_rebase_abort(RebaseHandle);
          raise;
        end;
      end;
    finally
      if Assigned(Signature) then git_signature_free(Signature);
      if Assigned(BranchHead) then git_annotated_commit_free(BranchHead);
      if Assigned(UpstreamHead) then git_annotated_commit_free(UpstreamHead);
    end;
  finally
    if Assigned(UpstreamRef) then git_reference_free(UpstreamRef);
  end;
end;

function TGitRepository.IsRebasing: Boolean;
var
  CurrentState: Integer;
begin
  // 1. Query the native state of the repository handle
  CurrentState := git_repository_state(FHandle);

  // 2. FIXED: Match the exact constant indices extracted from repository.inc!
  Result := (CurrentState = GIT_REPOSITORY_STATE_REBASE) or
            (CurrentState = GIT_REPOSITORY_STATE_REBASE_INTERACTIVE) or
            (CurrentState = GIT_REPOSITORY_STATE_REBASE_MERGE) or
            (CurrentState = GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE);
end;

procedure TGitRepository.RebaseContinue;
var
  RebaseHandle: Pgit_rebase;
  Signature: Pgit_signature;
begin
  RebaseHandle := nil;
  Signature := nil;

  // 1. Re-open the handle to the ongoing rebase operation currently stored in .git/
  CheckError(git_rebase_open(@RebaseHandle, FHandle, nil));
  try
    // Generate the standard author stamp to sign off the transaction
    CheckError(git_signature_now(@Signature, PAnsiChar(AnsiString(FDefaultAuthorName)), PAnsiChar(AnsiString(FDefaultAuthorEmail))));

    // 2. Finalize the transaction, rewrite the commit history timeline, and restore HEAD
    CheckError(git_rebase_finish(RebaseHandle, Signature));
  finally
    if Assigned(Signature) then git_signature_free(Signature);
    // Note: libgit2 internally disposes of the rebase handle inside git_rebase_finish on success,
    // but we wrap it defensively to prevent leaks if it throws a failure block.
    if Assigned(RebaseHandle) then git_rebase_free(RebaseHandle);
  end;
end;

procedure TGitRepository.RebaseAbort;
var
  RebaseHandle: Pgit_rebase;
begin
  RebaseHandle := nil;

  // 1. Re-open the handle to the ongoing transaction state
  CheckError(git_rebase_open(@RebaseHandle, FHandle, nil));
  try
    // 2. Erase all temporary files inside .git/ and force reset the files on disk back to safety!
    CheckError(git_rebase_abort(RebaseHandle));
  finally
    if Assigned(RebaseHandle) then git_rebase_free(RebaseHandle);
  end;
end;

procedure TGitRepository.Push(const RemoteName, BranchName: string);
var
  RemoteHandle: Pgit_remote;
  PushOpts: git_push_options;
  LocalRemoteName, LocalRefSpec: AnsiString;
  RefSpecArray: git_strarray;
  PCharRefSpec: PAnsiChar;
  ReflogMsg: AnsiString;
begin
  RemoteHandle := nil;
  LocalRemoteName := AnsiString(RemoteName);

  LocalRefSpec := AnsiString('refs/heads/' + BranchName + ':refs/heads/' + BranchName);
  PCharRefSpec := PAnsiChar(LocalRefSpec);
  RefSpecArray.strings := @PCharRefSpec;
  RefSpecArray.count := 1;

  CheckError(git_remote_lookup(@RemoteHandle, FHandle, PAnsiChar(LocalRemoteName)));
  try
    CheckError(git_push_options_init(@PushOpts, GIT_PUSH_OPTIONS_VERSION));

    FAnsiUser := AnsiString(FDefaultAuthorName);
    FAnsiToken := AnsiString(FGitToken);

    FAuthPayload.username := PAnsiChar(FAnsiUser);
    FAuthPayload.password := PAnsiChar(FAnsiToken);

    PushOpts.callbacks.credentials := @git_credential_userpass;
    PushOpts.callbacks.payload := @FAuthPayload;

    // 1. Transmit the packfile database data packets securely over to GitHub
    CheckError(git_remote_upload(RemoteHandle, @RefSpecArray, @PushOpts));

    ReflogMsg := AnsiString('update tips from push operation');

    // 2. 👈 THE CLEAN FIX: Uses the exact, official constant you discovered in your headers!
    // This satisfies the git_remote_autotag_option_t enum expectation perfectly.
    CheckError(git_remote_update_tips(
      RemoteHandle,
      @PushOpts.callbacks,
      1,
      GIT_REMOTE_DOWNLOAD_TAGS_UNSPECIFIED, // Natively documents that tag processing is ignored here
      PAnsiChar(ReflogMsg)
    ));

  finally
    if Assigned(RemoteHandle) then
      git_remote_free(RemoteHandle);
  end;
end;

procedure TGitRepository.Pull(const RemoteName: string; LogOutput: TStrings);
var
  CurrentBranchName: string;
  RemoteTrackingRef: string;
  RemoteRefObj: Pgit_reference;
  RemoteCommitObj: Pgit_commit;
  RemoteTreeObj: Pgit_tree;
  CheckoutOpts: git_checkout_options;

  // New variables for Fast-Forward Analysis mapping your library declarations
  AnalysisFlags: Cardinal; // Receives GIT_MERGE_ANALYSIS bitmask flags
  PreferenceFlags: Cardinal;
  AnnotatedHead: Pgit_annotated_commit;
  HeadsArray: array[0..0] of Pgit_annotated_commit;
  LocalBranchRef, NewLocalBranchRef: Pgit_reference;
begin
  RemoteRefObj := nil;
  RemoteCommitObj := nil;
  RemoteTreeObj := nil;
  AnnotatedHead := nil;
  LocalBranchRef := nil;
  NewLocalBranchRef := nil;
  AnalysisFlags := 0;
  PreferenceFlags := 0;

  // 1. PHASE 1: Downstream the cloud objects
  Fetch(RemoteName, LogOutput);

  CurrentBranchName := GetActiveBranchName;
  if (CurrentBranchName = '') or (Pos('Detached', CurrentBranchName) > 0) then
    raise EGitException.Create('Cannot complete Pull: Workspace is not standing on an active branch.');

  RemoteTrackingRef := 'refs/remotes/' + RemoteName + '/' + CurrentBranchName;

  // 2. EMPTY REPOSITORY GUARAD
  if git_repository_head_unborn(FHandle) = 1 then
  begin
    if Assigned(LogOutput) then
      LogOutput.Add('🌱 Empty repository detected. Performing initial checkout tracking setup from: ' + RemoteTrackingRef);

    if git_reference_lookup(@RemoteRefObj, FHandle, PAnsiChar(AnsiString(RemoteTrackingRef))) = 0 then
    begin
      try
        if (git_reference_peel(@RemoteCommitObj, RemoteRefObj, GIT_OBJECT_COMMIT) = 0) and
           (git_commit_tree(@RemoteTreeObj, RemoteCommitObj) = 0) then
        begin
          CheckError(git_checkout_options_init(@CheckoutOpts, GIT_CHECKOUT_OPTIONS_VERSION));
          CheckoutOpts.checkout_strategy := 1; // GIT_CHECKOUT_SAFE

          CheckError(git_checkout_tree(FHandle, Pgit_object(RemoteTreeObj), @CheckoutOpts));

          // Birth your local tracking branch
          CheckError(git_branch_create(nil, FHandle, PAnsiChar(AnsiString(CurrentBranchName)), RemoteCommitObj, 1));

          if Assigned(LogOutput) then
            LogOutput.Add('🚀 Initial pull completed successfully! Local workspace birthed and updated.');
          Exit;
        end;
      finally
        if Assigned(RemoteTreeObj) then git_tree_free(RemoteTreeObj);
        if Assigned(RemoteCommitObj) then git_commit_free(RemoteCommitObj);
        if Assigned(RemoteRefObj) then git_reference_free(RemoteRefObj);
      end;
    end;
  end;

  // 3. FAST-FORWARD ANALYSIS HANDSHAKE
  // Look up the remote tracking reference and wrap it inside an annotated commit descriptor
  CheckError(git_reference_lookup(@RemoteRefObj, FHandle, PAnsiChar(AnsiString(RemoteTrackingRef))));
  try
    CheckError(git_annotated_commit_from_ref(@AnnotatedHead, FHandle, RemoteRefObj));
    HeadsArray[0] := AnnotatedHead;

    // Ask libgit2 to analyze how the remote commit relates to our local HEAD pointer
    // This populates AnalysisFlags with bitmask values (GIT_MERGE_ANALYSIS_FASTFORWARD = 4)
    CheckError(git_merge_analysis(@AnalysisFlags, @PreferenceFlags, FHandle, @HeadsArray, 1));

    // CASE A: Already up to date!
    // GIT_MERGE_ANALYSIS_UP_TO_DATE = 2
    if (AnalysisFlags and 2) <> 0 then
    begin
      if Assigned(LogOutput) then
        LogOutput.Add('ℹ️ Already up to date.');
      Exit;
    end;

    // CASE B: THE FAST-FORWARD RESOLUTION!
    // GIT_MERGE_ANALYSIS_FASTFORWARD = 4
    if (AnalysisFlags and 4) <> 0 then
    begin
      if Assigned(LogOutput) then
        LogOutput.Add('⚡ Fast-forwarding local branch pointer matching CLI execution...');

      // Extract the target commit tree and run a clean checkout down to disk
      CheckError(git_reference_peel(@RemoteCommitObj, RemoteRefObj, GIT_OBJECT_COMMIT));
      CheckError(git_commit_tree(@RemoteTreeObj, RemoteCommitObj));

      CheckError(git_checkout_options_init(@CheckoutOpts, GIT_CHECKOUT_OPTIONS_VERSION));
      CheckoutOpts.checkout_strategy := 2; // GIT_CHECKOUT_FORCE to clear the stale staged tracking debris safely!

      CheckError(git_checkout_tree(FHandle, Pgit_object(RemoteTreeObj), @CheckoutOpts));

      // Advance your active local branch reference pointer to target the new remote commit ID hash
      CheckError(git_branch_lookup(@LocalBranchRef, FHandle, PAnsiChar(AnsiString(CurrentBranchName)), GIT_BRANCH_LOCAL));
      CheckError(git_reference_set_target(@NewLocalBranchRef, LocalBranchRef, git_commit_id(RemoteCommitObj), nil));

      if Assigned(LogOutput) then
        LogOutput.Add('🚀 Fast-forward completed successfully!');
      Exit;
    end;

  finally
    if Assigned(RemoteTreeObj) then git_tree_free(RemoteTreeObj);
    if Assigned(RemoteCommitObj) then git_commit_free(RemoteCommitObj);
    if Assigned(AnnotatedHead) then git_annotated_commit_free(AnnotatedHead);
    if Assigned(RemoteRefObj) then git_reference_free(RemoteRefObj);
    if Assigned(LocalBranchRef) then git_reference_free(LocalBranchRef);
  end;

  // 4. CASE C: THE HISTORIES HAVE TRULY DIVERGED -> Run standard multi-parent merge engine
  if Assigned(LogOutput) then
    LogOutput.Add('🧬 Histories diverged. Blending cloud updates from tracking reference: ' + RemoteTrackingRef);

  try
    MergeBranch(RemoteTrackingRef);
    if (git_repository_state(FHandle) = GIT_REPOSITORY_STATE_MERGE) then
    begin
      Commit('Merge remote-tracking branch ''' + RemoteTrackingRef + ''' into ' + CurrentBranchName, '', '');
    end;

    if Assigned(LogOutput) then
      LogOutput.Add('🚀 Pull operation completed and integrated successfully!');
  except
    on E: Exception do
    begin
      if Assigned(LogOutput) then
        LogOutput.Add('⚠️ Data downloaded, but file integration paused: ' + E.Message);
      raise;
    end;
  end;
end;

end.

