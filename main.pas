unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls, LazLogger,
  ExtCtrls, Buttons, SynEdit, Git.Engine, Git.DiffParser; // Pure Pascal tracking wrapper. Zero libgit2 raw C inclusions.

type
  { TForm1 }

  TForm1 = class(TForm)
    BtnSelectFolder: TButton;
    BtnValidate: TButton;
    BtnStageFile: TButton;
    BtnCommit: TButton;
    BtnUnstageFile: TButton;
    BtnDiscardChanges: TButton;
    BtnFetch: TButton;
    BtnNewBranch: TButton;
    BtnDeleteBranch: TButton;
    BtnSwitchBranch: TButton;
    BtnStashSave: TButton;
    BtnStashPop: TButton;
    BtnRenameBranch: TButton;
    BtnMergeBranch: TButton;
    BtnRebaseBranch: TButton;
    BtnRebaseContinue: TButton;
    BtnRebaseAbort: TButton;
    BtnPush: TButton;
    BtnPull: TButton;
    BtnClone: TButton;
    ComboBranches: TComboBox;
    ComboRemotes: TComboBox;
    EditUserName: TEdit;
    EditUserEmail: TEdit;
    EditRepoPath: TEdit;
    LabelRemote: TLabel;
    LabelBranches: TLabel;
    ListBoxNetworkLog: TListBox;
    ListViewHistory: TListView;
    ListViewStatus: TListView;
    MemoCommitMsg: TMemo;
    PageControlWorkspace: TPageControl;
    PanelTop: TPanel;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    Splitter1: TSplitter;
    StatusBar1: TStatusBar;
    SynEditDiff: TSynEdit;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    TabSheet3: TTabSheet;
    procedure BtnCloneClick(Sender: TObject);
    procedure BtnCommitClick(Sender: TObject);
    procedure BtnDeleteBranchClick(Sender: TObject);
    procedure BtnDiscardChangesClick(Sender: TObject);
    procedure BtnFetchClick(Sender: TObject);
    procedure BtnMergeBranchClick(Sender: TObject);
    procedure BtnNewBranchClick(Sender: TObject);
    procedure BtnPullClick(Sender: TObject);
    procedure BtnPushClick(Sender: TObject);
    procedure BtnRebaseAbortClick(Sender: TObject);
    procedure BtnRebaseBranchClick(Sender: TObject);
    procedure BtnRebaseContinueClick(Sender: TObject);
    procedure BtnRenameBranchClick(Sender: TObject);
    procedure BtnStageFileClick(Sender: TObject);
    procedure BtnStashPopClick(Sender: TObject);
    procedure BtnStashSaveClick(Sender: TObject);
    procedure BtnSwitchBranchClick(Sender: TObject);
    procedure BtnUnstageFileClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BtnSelectFolderClick(Sender: TObject);
    procedure BtnValidateClick(Sender: TObject);
    procedure ListViewHistoryCustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure ListViewStatusSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure SynEditDiffPaint(Sender: TObject; ACanvas: TCanvas);
    procedure SynEditDiffSpecialLineColors(Sender: TObject; Line: integer;
      var Special: boolean; var FG, BG: TColor);
  private
    FSessionToken: string; // Stores the Personal Access Token in RAM for this session
    FGraphList: TGitGraphArray;
    procedure RefreshUIFromRepo(Repo: TGitRepository);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  // The form window setup. No manual C library initialization sequences are needed here anymore!
  StatusBar1.SimpleText := 'No active repository.';
  BtnStageFile.Enabled := False;
  BtnUnstageFile.Enabled := False;
  BtnDiscardChanges.Enabled := False;
end;

procedure TForm1.BtnStageFileClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedFilePath: string;
begin
  // 1. Ensure the user actually selected a file from the status list view
  if not Assigned(ListViewStatus.Selected) then
  begin
    ShowMessage('Please select a modified or untracked file from the list first.');
    Exit;
  end;

  if EditRepoPath.Text = '' then Exit;

  // 2. Extract the file path string from Column 0 (the Caption)
  SelectedFilePath := ListViewStatus.Selected.Caption;

  try
    // 3. Open the safe Pascal repository handler instance
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // 4. Call our wrapper staging method (which executes git_index_add_bypath under the hood)
      Repo.StageFile(SelectedFilePath);

      // 5. Instantly refresh the UI to show the file is now 'Staged'
      BtnValidateClick(Sender);

      StatusBar1.SimpleText := 'Successfully staged: ' + SelectedFilePath;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('Staging Failed: ' + E.Message);
  end;
end;

procedure TForm1.BtnStashPopClick(Sender: TObject);
var
  Repo: TGitRepository;
begin
  if EditRepoPath.Text = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // Restore your work from the stash stack compartment
      Repo.StashPop;

      // 🔄 REFRESH: Your modified files are back, so repaint the changes grid!
      BtnValidateClick(Sender);

      StatusBar1.SimpleText := '📦 Stash successfully popped and restored into your workspace!';
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Stash Pop Failed: ' + E.Message + sLineBreak + sLineBreak +
                  '💡 Hint: Ensure you have an existing stash record layer stored, and that ' +
                  'restoring it won''t cause an unresolvable code file merge conflict.');
  end;
end;

procedure TForm1.BtnStashSaveClick(Sender: TObject);
var
  Repo: TGitRepository;
  StashComment: string;
begin
  if EditRepoPath.Text = '' then Exit;

  // Prompt the user for an optional quick description string for the stash bookmark
  StashComment := InputBox('Stash Changes', 'Enter an optional message to label this stash:', 'WIP Stash');
  StashComment := Trim(StashComment);
  if StashComment = '' then StashComment := 'WIP on ' + DateTimeToStr(Now);

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // Execute the stash operation
      Repo.StashSave(StashComment, EditUserName.Text, EditUserEmail.Text);

      // 🔄 REFRESH: The workspace files have been hidden away, so refresh the grid
      // lists to instantly demonstrate a 100% clean, pristine working tree!
      BtnValidateClick(Sender);

      StatusBar1.SimpleText := '📦 Workspace files safely stashed away: "' + StashComment + '"';
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Stash Save Failed: ' + E.Message + sLineBreak + sLineBreak +
                  '💡 Hint: Stashing requires you to have actual modified or staged file changes present.');
  end;
end;


procedure TForm1.BtnSwitchBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedBranch: string;
begin
  if EditRepoPath.Text = '' then Exit;
  if ComboBranches.Text = '' then Exit;

  SelectedBranch := ComboBranches.Text;

  // Proactively check if the user is clicking a branch they are already standing on
  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      if CompareText(SelectedBranch, Repo.GetActiveBranchName) = 0 then
      begin
        ShowMessage('ℹ️ You are already standing on branch "' + SelectedBranch + '".');
        Exit;
      end;

      StatusBar1.SimpleText := '🔀 Checking out branch "' + SelectedBranch + '"...';
      Application.ProcessMessages;

      // 1. Run the safe checkout tree modification down to disk
      Repo.SwitchToBranch(SelectedBranch);

      // 2. Trigger your master validation refresh loop to repaint all grids
      BtnValidateClick(Sender);
      StatusBar1.SimpleText := '✅ Switched to branch: ' + SelectedBranch;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        BtnValidateClick(Sender);
        ShowMessage('❌ Branch Switch Blocked: ' + E.Message + sLineBreak + sLineBreak +
                    '💡 Hint: Resolve your local uncommitted file conflicts before changing branches.');
      end;
  end;
end;


procedure TForm1.BtnCommitClick(Sender: TObject);
var
  Repo: TGitRepository;
begin
  if EditRepoPath.Text = '' then Exit;
  if Trim(MemoCommitMsg.Text) = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      if not Repo.HasStagedChanges then
      begin
        ShowMessage('⚠️ Cannot commit. There are no staged changes ready.');
        Exit;
      end;

      Repo.Commit(MemoCommitMsg.Text, EditUserName.Text, EditUserEmail.Text);

      MemoCommitMsg.Clear;
      BtnValidateClick(Sender);
      StatusBar1.SimpleText := '✅ Commit successfully created!';
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Commit Failed: ' + E.Message);
  end;
end;

procedure TForm1.BtnCloneClick(Sender: TObject);
var
  RemoteURL, LocalFolder, TargetToken, TargetUser: string;
  Repo: TGitRepository;
begin
  RemoteURL := InputBox('Clone Remote Repository', 'Enter the remote HTTPS repository URL:', '');
  RemoteURL := Trim(RemoteURL);
  if RemoteURL = '' then Exit;

  if not SelectDirectoryDialog1.Execute then Exit;
  LocalFolder := SelectDirectoryDialog1.FileName;
  TargetUser := EditUserName.Text;

  if FSessionToken = '' then
  begin
    if MessageDlg('Authentication', 'Does this repository require private access authentication?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      TargetToken := InputBox('Authentication Required', 'Enter your Personal Access Token (PAT):', '');
      FSessionToken := Trim(TargetToken);
    end;
  end;
  TargetToken := FSessionToken;

  ListBoxNetworkLog.Items.Clear;
  PageControlWorkspace.ActivePage := TabSheet3;
  StatusBar1.SimpleText := '📥 Cloning remote repository... Please wait...';
  Application.ProcessMessages;

  try
    // Downloads data packets and directly births your active, running object instance!
    Repo := TGitRepository.Clone(RemoteURL, LocalFolder, TargetUser, TargetToken, ListBoxNetworkLog.Items);
    try
      EditRepoPath.Text := LocalFolder;
      RefreshUIFromRepo(Repo); // Pass the live pointer straight through to paint the panels smoothly!
      ShowMessage('🎉 Clone operation completed and loaded successfully!');
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
    begin
      FSessionToken := '';
      StatusBar1.SimpleText := '❌ Clone failed.';
      ShowMessage('Clone Aborted: ' + E.Message);
    end;
  end;
end;


procedure TForm1.BtnDeleteBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  TargetBranch: string;
begin
  if EditRepoPath.Text = '' then Exit;

  // 1. Capture the text string currently visible inside your dropdown selection selector
  TargetBranch := ComboBranches.Text;
  if TargetBranch = '' then Exit;

  // 2. 👈 UX DESTRUCTIVE GUARD: Always verify actions before writing permanent data wipes
  if MessageDlg('Delete Local Branch',
                '⚠️ Are you absolutely sure you want to permanently delete the branch "' + TargetBranch + '"?' + sLineBreak +
                'All unmerged commit data tracking histories specific to this line will be deleted.',
                mtWarning, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit; // User aborted deletion window frame
  end;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // 3. Fire the backend erasure sequence
      Repo.DeleteBranch(TargetBranch);

      StatusBar1.SimpleText := '🔥 Deleted branch: ' + TargetBranch;

      // 4. Force a hard refresh to update the branch menu items and reset the dropdown focus safely
      ComboBranches.Items.Clear; // Force clear to break old cache assignments
      ComboBranches.Items.Assign(Repo.GetLocalBranchesList);

      // Automatically snap visual selection back to the repo's current actual active branch line
      ComboBranches.Text := Repo.GetActiveBranchName;

    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Branch Deletion Blocked: ' + E.Message);
  end;
end;

procedure TForm1.BtnDiscardChangesClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedFilePath: string;
begin
  if not Assigned(ListViewStatus.Selected) then Exit;
  if EditRepoPath.Text = '' then Exit;

  SelectedFilePath := ListViewStatus.Selected.Caption;

  // 👈 UX GUARD: Discarding changes is irreversible. Always prompt a confirmation box!
  if MessageDlg('Discard Changes',
                '⚠️ Are you absolutely sure you want to undo all local modifications inside "' + SelectedFilePath + '"?' + sLineBreak +
                'This operation cannot be undone and your unsaved changes will be lost permanently.',
                mtWarning, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit; // User aborted safety window
  end;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // Execute the forced checkout reset
      Repo.DiscardChanges(SelectedFilePath);

      // Automatically rebuild and update our workspace layout views
      BtnValidateClick(Sender);
      StatusBar1.SimpleText := '♻️ Reverted file: ' + SelectedFilePath;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('Discard Operations Failed: ' + E.Message);
  end;
end;

procedure TForm1.BtnFetchClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedRemote: string;
begin
  if EditRepoPath.Text = '' then Exit;
  if ComboRemotes.Text = '' then Exit;

  SelectedRemote := ComboRemotes.Text;
  ListBoxNetworkLog.Items.Clear;
  PageControlWorkspace.ActivePage := TabSheet3;

  StatusBar1.SimpleText := '📡 Syncing with remote repository...';
  Application.ProcessMessages;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // Pass your session token buffer down into the class (might be empty, which is fine!)
      Repo.GitToken := FSessionToken;

      // Try running the operation anonymously or with our active cache
      Repo.Fetch(SelectedRemote, ListBoxNetworkLog.Items);

      StatusBar1.SimpleText := '✅ Fetch completed successfully from: ' + SelectedRemote;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        // 👈 THE LAZY AUTHENTICATION INTERCEPTOR:
        // Detect if the server rejected the connection due to missing authorization credentials
        if (Pos('Auth', E.Message) > 0) or (Pos('auth', E.Message) > 0) or (Pos('401', E.Message) > 0) or (Pos('-16', E.Message) > 0) then
        begin
          StatusBar1.SimpleText := '🔑 Authentication required...';

          FSessionToken := InputBox('GitHub Authentication Required',
                                    'This repository requires authorization keys.' + sLineBreak +
                                    'Please enter your GitHub Personal Access Token (PAT):', '');
          FSessionToken := Trim(FSessionToken);

          if FSessionToken <> '' then
          begin
            StatusBar1.SimpleText := '🔄 Token authenticated! Please click "Fetch" again to complete.';
            ListBoxNetworkLog.Items.Add('🔒 Token successfully saved to session cache. Please click "Fetch" again.');
          end
          else
            StatusBar1.SimpleText := '❌ Fetch canceled by user.';
        end
        else
        begin
          StatusBar1.SimpleText := '❌ Remote connection failed.';
          ListBoxNetworkLog.Items.Add('❌ Network Pipeline Error: ' + E.Message);
        end;
      end;
  end;
end;

procedure TForm1.BtnMergeBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  TargetBranch, CurrentBranch: string;
begin
  if EditRepoPath.Text = '' then Exit;

  TargetBranch := ComboBranches.Text;
  if TargetBranch = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      CurrentBranch := Repo.GetActiveBranchName;

      // 👈 UX GUARD: Block users from trying to merge a branch into itself
      if CompareText(TargetBranch, CurrentBranch) = 0 then
      begin
        ShowMessage('⚠️ Cannot merge. "' + TargetBranch + '" is your currently active branch.' + sLineBreak +
                    'Please select an ALTERNATE branch from the dropdown list to merge into your current workspace.');
        Exit;
      end;

      // Prompt a clear confirmation before merging
      if MessageDlg('Merge Branch',
                    'Do you want to merge changes from branch "' + TargetBranch + '" into your active branch "' + CurrentBranch + '"?',
                    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

      StatusBar1.SimpleText := '🧬 Merging branch "' + TargetBranch + '" into "' + CurrentBranch + '"...';
      Application.ProcessMessages;

      // Execute the native merge action loop
      Repo.MergeBranch(TargetBranch);

      // 🔄 REFRESH EVERYTHING: Repaint all lists to display the new staged files
      BtnValidateClick(Sender);

      // Pre-populate your commit memo box with standard Git merge syntax automatically!
      MemoCommitMsg.Text := 'Merge branch ''' + TargetBranch + ''' into ' + CurrentBranch;

      ShowMessage('✅ Merge prepared successfully!' + sLineBreak + sLineBreak +
                  'The modified contents have been placed into your staging index.' + sLineBreak +
                  'Review the changes, verify your commit message, and click "Commit" to finalize the merge.');

    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        BtnValidateClick(Sender);
        ShowMessage('❌ Merge Blocked or Failed: ' + E.Message + sLineBreak + sLineBreak +
                    '💡 Hint: If there are structural merge conflicts, the files will be marked in your list view.');
      end;
  end;
end;

procedure TForm1.BtnNewBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  InputName: string;
begin
  if EditRepoPath.Text = '' then Exit;

  // 1. Open a safe native cross-platform input dialog prompt screen frame
  InputName := InputBox('Create Local Branch', 'Enter the name for your new branch:', '');

  // 2. Clear whitespace tracking blocks and exit if the user clicked cancel or left it empty
  InputName := Trim(InputName);
  if InputName = '' then Exit;

  // 3. Basic name formatting check to guard against common illegal Git character inputs
  if (Pos(' ', InputName) > 0) or (Pos('..', InputName) > 0) then
  begin
    ShowMessage('⚠️ Invalid branch name. Git branch names cannot contain spaces or sequential dots.');
    Exit;
  end;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // 4. Create the local tracking reference branch node on disk
      Repo.CreateBranch(InputName);

      // 5. Force rebuild your dropdown menu arrays to pick up the newly injected option string
      ComboBranches.Items.Assign(Repo.GetLocalBranchesList);

      // 6. Automatically select and switch focus directly onto your new line
      ComboBranches.Text := InputName;
      BtnSwitchBranchClick(Sender); // Explicitly invoke change trigger to run checkout setups

      StatusBar1.SimpleText := '✅ Created and checked out new branch: ' + InputName;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Branch Creation Failed: ' + E.Message + sLineBreak + sLineBreak +
                  '💡 Hint: Verify the name does not already match an existing tracking line.');
  end;
end;

procedure TForm1.BtnPullClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedRemote: string;
begin
  if EditRepoPath.Text = '' then Exit;
  if ComboRemotes.Text = '' then Exit;

  SelectedRemote := ComboRemotes.Text;
  ListBoxNetworkLog.Items.Clear;
  PageControlWorkspace.ActivePage := TabSheet3;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      Repo.GitToken := FSessionToken;

      // Try to execute the combined fast-forward analysis and pull merge engine
      Repo.Pull(SelectedRemote, ListBoxNetworkLog.Items);

      BtnValidateClick(Sender);
      StatusBar1.SimpleText := '✅ Pull completed successfully from ' + SelectedRemote;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        if (Pos('Auth', E.Message) > 0) or (Pos('auth', E.Message) > 0) or (Pos('401', E.Message) > 0) or (Pos('-16', E.Message) > 0) then
        begin
          FSessionToken := InputBox('GitHub Authentication Required',
                                    'This repository requires authorization keys.' + sLineBreak +
                                    'Please enter your GitHub Personal Access Token (PAT):', '');
          FSessionToken := Trim(FSessionToken);

          if FSessionToken <> '' then
            StatusBar1.SimpleText := '🔄 Token authenticated! Please click "Pull" again to synchronize.'
          else
            StatusBar1.SimpleText := '❌ Pull canceled by user.';
        end
        else
        begin
          StatusBar1.SimpleText := '❌ Pull operation failed.';
          ShowMessage('Pull Operation Interrupted: ' + E.Message);
        end;
      end;
  end;
end;

procedure TForm1.BtnPushClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedRemote, ActiveBranch: string;
begin
  if EditRepoPath.Text = '' then Exit;
  if ComboRemotes.Text = '' then Exit;

  SelectedRemote := ComboRemotes.Text;
  ListBoxNetworkLog.Items.Clear;
  PageControlWorkspace.ActivePage := TabSheet3;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      Repo.GitToken := FSessionToken;
      ActiveBranch := Repo.GetActiveBranchName;
      ListBoxNetworkLog.Items.Add('📤 Preparing data transport packs for branch: ' + ActiveBranch);
      Application.ProcessMessages;

      Repo.Push(SelectedRemote, ActiveBranch);

      StatusBar1.SimpleText := '✅ Push completed successfully!';
      ListBoxNetworkLog.Items.Add('🎉 Server upload completed! Your remote repository branch is up to date.');
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        if (Pos('Auth', E.Message) > 0) or (Pos('auth', E.Message) > 0) or (Pos('401', E.Message) > 0) or (Pos('-16', E.Message) > 0) then
        begin
          FSessionToken := InputBox('GitHub Authentication Required',
                                    'Pushing code requires server write access authorization.' + sLineBreak +
                                    'Please enter your GitHub Personal Access Token (PAT):', '');
          FSessionToken := Trim(FSessionToken);

          if FSessionToken <> '' then
            StatusBar1.SimpleText := '🔄 Token authenticated! Please click "Push" again to upload.'
          else
            StatusBar1.SimpleText := '❌ Push canceled by user.';
        end
        else
        begin
          StatusBar1.SimpleText := '❌ Push operation failed.';
          ListBoxNetworkLog.Items.Add('❌ Network Transport Error: ' + E.Message);
        end;
      end;
  end;
end;

procedure TForm1.BtnRebaseAbortClick(Sender: TObject);
var
  Repo: TGitRepository;
begin
  if EditRepoPath.Text = '' then Exit;

  if MessageDlg('Abort Ongoing Rebase',
                '⚠️ Are you sure you want to abort this rebase?' + sLineBreak +
                'This will undo the transaction and reset your files back to how they were before the rebase started.',
                mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      StatusBar1.SimpleText := '♻️ Aborting rebase transaction and resetting workdir...';
      Application.ProcessMessages;

      // Wipe out the temporary rebase state files
      Repo.RebaseAbort;

      BtnValidateClick(Sender);
      ShowMessage('✅ Rebase aborted. Your repository has been safely restored to its original state.');
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Abort Rebase Failed: ' + E.Message);
  end;
end;


procedure TForm1.BtnRebaseBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  TargetUpstreamBranch, CurrentBranch: string;
begin
  if EditRepoPath.Text = '' then Exit;

  TargetUpstreamBranch := ComboBranches.Text;
  if TargetUpstreamBranch = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      CurrentBranch := Repo.GetActiveBranchName;

      // UX GUARD: Prevent rebasing a branch onto itself
      if CompareText(TargetUpstreamBranch, CurrentBranch) = 0 then
      begin
        ShowMessage('⚠️ Cannot rebase. You are already standing on branch "' + TargetUpstreamBranch + '".' + sLineBreak +
                    'Please select an ALTERNATE baseline branch from the dropdown list to rebase your current work onto.');
        Exit;
      end;

      // Destructive/Rewriting history action warning confirmation prompt window
      if MessageDlg('Rebase Branch History',
                    '⚠️ Warning: This will rewrite local commit history!' + sLineBreak + sLineBreak +
                    'Do you want to rebase your current active branch "' + CurrentBranch + '" onto the top of "' + TargetUpstreamBranch + '"?',
                    mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;

      StatusBar1.SimpleText := '🥞 Rebasing commits from "' + CurrentBranch + '" onto "' + TargetUpstreamBranch + '"...';
      Application.ProcessMessages;

      // 🚀 Run the stateful transaction rebase loop
      Repo.RebaseBranch(TargetUpstreamBranch);

      // 🔄 FORCE SYSTEM REFRESH: Repaint all tracking logs, grids, and history tables instantly
      BtnValidateClick(Sender);

      StatusBar1.SimpleText := '✅ Rebase completed successfully!';
      ShowMessage('🎉 Rebase complete! Your branch history timeline has been successfully rewritten and aligned.');

    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      begin
        BtnValidateClick(Sender);
        ShowMessage('❌ Rebase Operation Failed/Aborted: ' + E.Message + sLineBreak + sLineBreak +
                    '💡 Hint: If a commit patch introduced a collision or structural merge conflict, ' +
                    'the rebase operation was safely aborted to preserve your original repository state.');
      end;
  end;
end;

procedure TForm1.BtnRebaseContinueClick(Sender: TObject);
var
  Repo: TGitRepository;
begin
  if EditRepoPath.Text = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      StatusBar1.SimpleText := '🥞 Finalizing and committing rebase timeline...';
      Application.ProcessMessages;

      // Execute the native finish routine
      Repo.RebaseContinue;

      // 🔄 FORCE REFRESH: History has rewritten, update the tables instantly!
      BtnValidateClick(Sender);
      ShowMessage('🎉 Rebase successfully completed and recorded into history!');
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Continue Rebase Failed: ' + E.Message);
  end;
end;



procedure TForm1.BtnRenameBranchClick(Sender: TObject);
var
  Repo: TGitRepository;
  CurrentSelectedBranch, NewName: string;
begin
  if EditRepoPath.Text = '' then Exit;

  CurrentSelectedBranch := ComboBranches.Text;
  if CurrentSelectedBranch = '' then Exit;

  // 1. Open a safe native cross-platform input dialog prompt screen frame
  NewName := InputBox('Rename Local Branch', 'Enter the new name for branch "' + CurrentSelectedBranch + '":', CurrentSelectedBranch);
  NewName := Trim(NewName);

  // 2. Abort if empty or if they didn't change the name
  if (NewName = '') or (CompareText(NewName, CurrentSelectedBranch) = 0) then Exit;

  // 3. Basic formatting validation block
  if (Pos(' ', NewName) > 0) or (Pos('..', NewName) > 0) then
  begin
    ShowMessage('⚠️ Invalid branch name. Git branch names cannot contain spaces or sequential dots.');
    Exit;
  end;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // 4. Fire the backend relocation engine
      Repo.RenameBranch(CurrentSelectedBranch, NewName);

      StatusBar1.SimpleText := '🏷️ Renamed branch "' + CurrentSelectedBranch + '" to "' + NewName + '"';

      // 5. Force rebuild your dropdown menu arrays to clear out the obsolete tracking string
      ComboBranches.Items.Clear;
      ComboBranches.Items.Assign(Repo.GetLocalBranchesList);

      // 6. Automatically select the updated name inside your dropdown view layout
      ComboBranches.Text := NewName;
      BtnValidateClick(Sender); // Refresh grids in case it was the active branch line

    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('❌ Branch Rename Failed: ' + E.Message);
  end;
end;


procedure TForm1.BtnUnstageFileClick(Sender: TObject);
var
  Repo: TGitRepository;
  SelectedFilePath: string;
begin
  // 1. Ensure a file is selected to unstage
  if not Assigned(ListViewStatus.Selected) then
  begin
    ShowMessage('Please select a staged file from the list first.');
    Exit;
  end;

  if EditRepoPath.Text = '' then Exit;
  SelectedFilePath := ListViewStatus.Selected.Caption;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      // 2. Call our wrapper unstaging routine
      Repo.UnstageFile(SelectedFilePath);

      // 3. Instantly refresh both panels
      BtnValidateClick(Sender);
      StatusBar1.SimpleText := 'Successfully unstaged: ' + SelectedFilePath;
    finally
      Repo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('Unstaging Failed: ' + E.Message);
  end;
end;

procedure TForm1.BtnSelectFolderClick(Sender: TObject);
var
  TargetDirectory: string;
  Repo: TGitRepository;
begin
  if SelectDirectoryDialog1.Execute then
  begin
    TargetDirectory := SelectDirectoryDialog1.FileName;
    EditRepoPath.Text := TargetDirectory;

    if not DirectoryExists(TargetDirectory + '/.git') then
    begin
      if MessageDlg('Initialize Repository', 'Initialize a brand-new repository here?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        try
          // Spawns the folder and returns a fully initialized, live object instance!
          Repo := TGitRepository.Init(TargetDirectory);
          try
            RefreshUIFromRepo(Repo); // Paint the screen using our live object handles instantly!
          finally
            Repo.Free;
          end;
        except
          on E: Exception do ShowMessage(E.Message);
        end;
      end;
    end
    else
      BtnValidateClick(Sender);
  end;
end;


procedure TForm1.BtnValidateClick(Sender: TObject);
var
  Repo: TGitRepository;
begin
  if EditRepoPath.Text = '' then Exit;
  try
    Repo := TGitRepository.Open(EditRepoPath.Text);
    try
      RefreshUIFromRepo(Repo);
    finally
      Repo.Free;
    end;
  except
    on E: Exception do ShowMessage('Error opening repo: ' + E.Message);
  end;
end;

procedure TForm1.ListViewHistoryCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
const
  LANE_WIDTH = 14; //14;       // px between lane centers — wide enough for radius-4 circles
  LANE_OFFSET = 10; //10;      // left margin before lane 0
  CIRCLE_RADIUS = 4; //4;
  PEN_WIDTH = 2; //2;
  LANE_COLORS: array[0..4] of TColor = (
    clBlue, $0000A5FF {Orange}, clGreen, clPurple, clTeal
  );
var
  NodeIndex, LaneX, ParentLaneX, RowTopY, RowBottomY, RowMidY: Integer;
  NodeColor, PassColor: TColor;
  RowBounds, ClipBounds: TRect;
  MaxLane, I, J, ColLeft: Integer;
  CellText: string;
  TextStyle: TTextStyle;
  IsParentLane: Boolean;
begin
  DefaultDraw := False;
  if Item.Index < 0 then Exit;

  NodeIndex := Item.Index;
  if NodeIndex > High(FGraphList) then Exit;

  RowBounds  := Item.DisplayRect(drBounds);
  RowTopY    := RowBounds.Top;
  RowBottomY := RowBounds.Bottom;
  RowMidY    := RowTopY + (RowBounds.Height div 2);

  MaxLane := 0;
  for I := 0 to High(FGraphList) do
  begin
    if FGraphList[I].GraphLane > MaxLane then
      MaxLane := FGraphList[I].GraphLane;
    for J := 0 to High(FGraphList[I].ActiveLanes) do
      if FGraphList[I].ActiveLanes[J] <> '' then
        if J > MaxLane then MaxLane := J;
  end;
  ListViewHistory.Columns[0].Width := 10 + (MaxLane + 1) * 14 + 14;


  // ── 1. BACKGROUND ──────────────────────────────────────────────────────────
  if cdsSelected in State then
  begin
    Sender.Canvas.Brush.Color := clHighlight;
    Sender.Canvas.Font.Color  := clHighlightText;
  end
  else
  begin
    Sender.Canvas.Brush.Color := Sender.Color;
    Sender.Canvas.Font.Color  := Sender.Font.Color;
  end;
  Sender.Canvas.FillRect(RowBounds);

  // ── 2. PASSTHROUGH LINES ───────────────────────────────────────────────────
  // Draw full-height verticals for lanes that are simply passing through.
  // A lane passes through if it is active (non-empty in ActiveLanes) AND
  // is neither this node's lane nor a parent-destination lane.
  for I := 0 to High(FGraphList[NodeIndex].ActiveLanes) do
  begin
    // Only draw passthrough for lanes that are neither this node's lane
    // nor a parent destination (those are handled by steps 3 and 4)
    if I = FGraphList[NodeIndex].GraphLane then Continue;

    IsParentLane := False;
    for J := 0 to High(FGraphList[NodeIndex].ParentLanes) do
      if FGraphList[NodeIndex].ParentLanes[J] = I then
      begin
        IsParentLane := True;
        Break;
      end;
    if IsParentLane then Continue;

    PassColor := LANE_COLORS[I mod Length(LANE_COLORS)];
    LaneX := RowBounds.Left + LANE_OFFSET + I * LANE_WIDTH;
    Sender.Canvas.Pen.Color := PassColor;
    Sender.Canvas.Pen.Width := PEN_WIDTH;

    // Top half: lane must appear in IncomingLanes (arrived from above)
    if (I <= High(FGraphList[NodeIndex].IncomingLanes)) and
       (FGraphList[NodeIndex].IncomingLanes[I] <> '') then
    begin
      Sender.Canvas.MoveTo(LaneX, RowTopY);
      Sender.Canvas.LineTo(LaneX, RowMidY);
    end;

    // Bottom half: lane must appear in ActiveLanes (continues below)
    if (I <= High(FGraphList[NodeIndex].ActiveLanes)) and
       (FGraphList[NodeIndex].ActiveLanes[I] <> '') then
    begin
      Sender.Canvas.MoveTo(LaneX, RowMidY);
      Sender.Canvas.LineTo(LaneX, RowBottomY);
    end;
  end;

  // ── 3. NODE LANE VERTICAL SEGMENTS ─────────────────────────────────────────
  NodeColor := LANE_COLORS[FGraphList[NodeIndex].GraphLane mod Length(LANE_COLORS)];
  LaneX     := RowBounds.Left + LANE_OFFSET + FGraphList[NodeIndex].GraphLane * LANE_WIDTH;
  Sender.Canvas.Pen.Color := NodeColor;
  Sender.Canvas.Pen.Width := PEN_WIDTH;

  // Top half: this lane must have been incoming from above
  if (NodeIndex > 0) and
     (FGraphList[NodeIndex].GraphLane <= High(FGraphList[NodeIndex].IncomingLanes)) and
     (FGraphList[NodeIndex].IncomingLanes[FGraphList[NodeIndex].GraphLane] <> '') then
  begin
    Sender.Canvas.MoveTo(LaneX, RowTopY);
    Sender.Canvas.LineTo(LaneX, RowMidY);
  end;

  // Bottom half: first parent continues on this same lane
  if (Length(FGraphList[NodeIndex].ParentIds) > 0) and
     (Length(FGraphList[NodeIndex].ParentLanes) > 0) and
     (FGraphList[NodeIndex].ParentLanes[0] = FGraphList[NodeIndex].GraphLane) then
  begin
    Sender.Canvas.MoveTo(LaneX, RowMidY);
    Sender.Canvas.LineTo(LaneX, RowBottomY);
  end;

  // ── 4. MERGE / BRANCH ELBOW LINES ──────────────────────────────────────────
  for J := 0 to High(FGraphList[NodeIndex].ParentLanes) do
  begin
    ParentLaneX := RowBounds.Left + LANE_OFFSET + FGraphList[NodeIndex].ParentLanes[J] * LANE_WIDTH;
    if ParentLaneX = LaneX then Continue;

    // DEBUG — log what IncomingLanes holds for this parent lane
    {DebugLogger.LogName := 'drawdebug.log';
    if FGraphList[NodeIndex].ParentLanes[J] <= High(FGraphList[NodeIndex].IncomingLanes) then
      DebugLn('Row ', AnsiString(IntToStr(NodeIndex)),
              ' ParentLane ', AnsiString(IntToStr(FGraphList[NodeIndex].ParentLanes[J])),
              ' IncomingLanes value = "',
              AnsiString(FGraphList[NodeIndex].IncomingLanes[FGraphList[NodeIndex].ParentLanes[J]]),
              '"')
    else
      DebugLn('Row ', AnsiString(IntToStr(NodeIndex)),
              ' ParentLane ', AnsiString(IntToStr(FGraphList[NodeIndex].ParentLanes[J])),
              ' is OUT OF BOUNDS for IncomingLanes (High=',
              AnsiString(IntToStr(High(FGraphList[NodeIndex].IncomingLanes))), ')');}


    if J = 0 then
      Sender.Canvas.Pen.Color := NodeColor
    else
      Sender.Canvas.Pen.Color := LANE_COLORS[FGraphList[NodeIndex].ParentLanes[J] mod Length(LANE_COLORS)];
    Sender.Canvas.Pen.Width := PEN_WIDTH;

    // Draw the TOP half: incoming vertical from top of row down to node center.
    // This is the segment that arrives into the merge node from the branch above.
    // Without this, the branch lane has a gap in the merge row itself.
    // Only draw the arriving top-half if that lane was already active above
    // Top half of parent lane arriving into this merge node
    if (FGraphList[NodeIndex].ParentLanes[J] <= High(FGraphList[NodeIndex].IncomingLanes)) and
       (FGraphList[NodeIndex].IncomingLanes[FGraphList[NodeIndex].ParentLanes[J]] <> '') then
    begin
      Sender.Canvas.MoveTo(ParentLaneX, RowTopY);
      Sender.Canvas.LineTo(ParentLaneX, RowBottomY - 2);
    end;

    // Draw the elbow: from node center across and down to row bottom.
    // Bend at the lower quarter of the row for a clean diagonal-free look.
    Sender.Canvas.MoveTo(LaneX, RowMidY);
    Sender.Canvas.LineTo(LaneX, RowBottomY - 2);
    Sender.Canvas.LineTo(ParentLaneX, RowBottomY - 2);
    Sender.Canvas.LineTo(ParentLaneX, RowBottomY);

  end;
  // ── 5. COMMIT CIRCLE ───────────────────────────────────────────────────────
  // Draw circle last so it sits on top of the lines
  LaneX := RowBounds.Left + LANE_OFFSET + FGraphList[NodeIndex].GraphLane * LANE_WIDTH;
  Sender.Canvas.Brush.Color := NodeColor;
  Sender.Canvas.Pen.Color   := NodeColor;
  Sender.Canvas.Pen.Width   := PEN_WIDTH div 2; //1;
  Sender.Canvas.Ellipse(LaneX - CIRCLE_RADIUS, RowMidY - CIRCLE_RADIUS,
                        LaneX + CIRCLE_RADIUS, RowMidY + CIRCLE_RADIUS);

  if cdsSelected in State then
  begin
    Sender.Canvas.Brush.Style := bsClear;
    Sender.Canvas.Pen.Color   := clWhite;
    Sender.Canvas.Ellipse(LaneX - CIRCLE_RADIUS - 2, RowMidY - CIRCLE_RADIUS - 2,
                          LaneX + CIRCLE_RADIUS + 2, RowMidY + CIRCLE_RADIUS + 2);
  end;

  // ── 6. TEXT COLUMNS ────────────────────────────────────────────────────────
  TextStyle            := Sender.Canvas.TextStyle;
  TextStyle.SingleLine := True;
  TextStyle.EndEllipsis := True;
  TextStyle.Clipping   := True;
  TextStyle.WordBreak  := False;
  TextStyle.Layout     := tlCenter;

  if cdsSelected in State then
    Sender.Canvas.Font.Color := clHighlightText
  else
    Sender.Canvas.Font.Color := Sender.Font.Color;

  ColLeft := RowBounds.Left + TListView(Sender).Columns[0].Width;

  for I := 1 to 4 do
  begin
    if I >= TListView(Sender).Columns.Count then Break;

    ClipBounds.Left   := ColLeft + 6;
    ClipBounds.Top    := RowTopY;
    ClipBounds.Right  := ColLeft + TListView(Sender).Columns[I].Width - 6;
    ClipBounds.Bottom := RowBottomY;

    case I of
      1: CellText := FGraphList[NodeIndex].Message;
      2: CellText := FGraphList[NodeIndex].Author;
      3: CellText := DateTimeToStr(FGraphList[NodeIndex].Timestamp);
      4: if Length(FGraphList[NodeIndex].ParentIds) = 0 then
           CellText := '[Root Commit]'
         else if Length(FGraphList[NodeIndex].ParentIds) = 1 then
           CellText := 'Parent: ' + Copy(FGraphList[NodeIndex].ParentIds[0], 1, 7)
         else
           CellText := 'Merge: ' + Copy(FGraphList[NodeIndex].ParentIds[0], 1, 7)
                     + ' + ' + Copy(FGraphList[NodeIndex].ParentIds[1], 1, 7);
    end;

    Sender.Canvas.TextRect(ClipBounds, ClipBounds.Left, RowTopY, CellText, TextStyle);
    Inc(ColLeft, TListView(Sender).Columns[I].Width);
  end;

  // ── 7. RESET CANVAS STATE ──────────────────────────────────────────────────
  Sender.Canvas.Brush.Style := bsSolid;
  Sender.Canvas.Pen.Width   := 1;
  Sender.Canvas.Pen.Color   := clBlack;
  Sender.Canvas.Brush.Color := Sender.Color;
end;

procedure TForm1.ListViewStatusSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  StateStr: string;
  Repo: TGitRepository;
  DiffText: string;
begin
  // --- KEEP YOUR EXISTING DISABLING/ENABLING GUARDRAILS ---
  if (not Selected) or (not Assigned(Item)) then
  begin
    BtnStageFile.Enabled := False;
    BtnUnstageFile.Enabled := False;
    BtnDiscardChanges.Enabled := False;
    Exit;
  end;

  if Item.SubItems.Count > 0 then
  begin
    StateStr := Item.SubItems[0];
    if Pos('Staged', StateStr) > 0 then
    begin
      BtnStageFile.Enabled := False;
      BtnUnstageFile.Enabled := True;
      BtnDiscardChanges.Enabled := False;
    end
    else
    begin
      BtnStageFile.Enabled := True;
      BtnUnstageFile.Enabled := False;
      BtnDiscardChanges.Enabled := (StateStr = 'Modified') or (StateStr = 'Deleted');
    end;
  end;
  // ---------------------------------------------------------

  // NEW: TRIGGER THE DYNAMIC DIFF EXTRACTION PIPELINE
  if Selected and (EditRepoPath.Text <> '') then
  begin
    try
      Repo := TGitRepository.Open(EditRepoPath.Text);
      try
        DiffText := Repo.GetFileDiff(Item.Caption);
        SynEditDiff.Text := DiffText;

        // Proactively flip tabs over to 'File Differences' if a modification exists
        if DiffText <> '' then
          PageControlWorkspace.ActivePage := PageControlWorkspace.Pages[1];

      finally
        Repo.Free;
      end;
    except
      on E: Exception do
        SynEditDiff.Text := 'Unable to calculate diff map: ' + E.Message;
    end;
  end;
end;

procedure TForm1.SynEditDiffPaint(Sender: TObject; ACanvas: TCanvas);
var
  Y, LineNum, NextLineNum, LookAheadLimit: Integer;
  CurrentLineText, NextLineText: string;
  OldMap, NewMap: TCharMatchArray;
  I: Integer;
  CharWidth, LineHeight: Integer;
  CalculatedLinesInView: Integer;
  TextCoordPoint: TPoint;
  TextPosition: TPoint;
begin
  CharWidth := SynEditDiff.CharWidth;
  LineHeight := SynEditDiff.LineHeight;

  if LineHeight <= 0 then Exit;

  CalculatedLinesInView := SynEditDiff.Height div LineHeight;

  for Y := 0 to CalculatedLinesInView do
  begin
    LineNum := SynEditDiff.TopLine + Y;
    if (LineNum < 1) or (LineNum > SynEditDiff.Lines.Count) then Continue;

    CurrentLineText := SynEditDiff.Lines[LineNum - 1];

    if (Length(CurrentLineText) > 0) and (CurrentLineText[1] = '-') then
    begin
      if (Pos('--- a/', CurrentLineText) = 1) or (Pos('--- /dev/null', CurrentLineText) = 1) then
        Continue;

      // 👈 FIXED LOOK-AHEAD LIMIT:
      // Only look ahead up to 5 lines maximum. If a deletion block is larger than this,
      // it means it's a massive replacement or a whole-file swap, so don't force a bad match.
      LookAheadLimit := LineNum + 5;
      if LookAheadLimit > SynEditDiff.Lines.Count then
        LookAheadLimit := SynEditDiff.Lines.Count;

      NextLineNum := LineNum + 1;
      while NextLineNum <= LookAheadLimit do
      begin
        NextLineText := SynEditDiff.Lines[NextLineNum - 1];

        // If we hit a brand new git file diff block, abort look-ahead immediately
        if (Pos('diff --git', NextLineText) = 1) then Break;

        if (Length(NextLineText) > 0) and (NextLineText[1] = '+') then
        begin
          if Pos('+++ b/', NextLineText) = 1 then
          begin
            Inc(NextLineNum);
            Continue;
          end;

          // Run the matching engine with our new similarity threshold
          if TGitDiffMatcher.CompareLines(CurrentLineText, NextLineText, OldMap, NewMap) then
          begin
            // Draw deleted character variances
            ACanvas.Brush.Color := TColor($9999FF);
            ACanvas.Brush.Style := bsSolid;

            for I := 0 to High(OldMap) do
            begin
              if OldMap[I].State = ccDeleted then
              begin
                TextPosition.X := I + 2;
                TextPosition.Y := LineNum;

                TextCoordPoint := SynEditDiff.RowColumnToPixels(TextPosition);
                ACanvas.FillRect(Bounds(TextCoordPoint.X, TextCoordPoint.Y, CharWidth, LineHeight));

                ACanvas.Font.Color := clMaroon;
                ACanvas.TextOut(TextCoordPoint.X, TextCoordPoint.Y, OldMap[I].Character);
              end;
            end;

            // Draw added character variances
            ACanvas.Brush.Color := TColor($77FF77);
            for I := 0 to High(NewMap) do
            begin
              if NewMap[I].State = ccAdded then
              begin
                TextPosition.X := I + 2;
                TextPosition.Y := NextLineNum;

                TextCoordPoint := SynEditDiff.RowColumnToPixels(TextPosition);
                ACanvas.FillRect(Bounds(TextCoordPoint.X, TextCoordPoint.Y, CharWidth, LineHeight));

                ACanvas.Font.Color := clGreen;
                ACanvas.TextOut(TextCoordPoint.X, TextCoordPoint.Y, NewMap[I].Character);
              end;
            end;
          end;
          Break; // Match evaluated, break out of look-ahead loop
        end;

        Inc(NextLineNum);
      end;
    end;
  end;
end;

procedure TForm1.SynEditDiffSpecialLineColors(Sender: TObject; Line: integer;
  var Special: boolean; var FG, BG: TColor);
var
  LineText: string;
begin
  // 1. Fetch the raw line text out of the component's active memory list using the Line index.
  // Note: SynEdit lines array is 0-indexed, but the Line index passed here is 1-indexed.
  if (Line - 1 >= 0) and (Line - 1 < SynEditDiff.Lines.Count) then
    LineText := SynEditDiff.Lines[Line - 1]
  else
    Exit;

  if LineText = '' then Exit;

  // 2. Evaluate the first character of the text, exactly like our previous logic
  case LineText[1] of
    '+': // Injected Line (Addition)
      begin
        Special := True;
        FG := clGreen;                      // Text color (FG)
        BG := TColor($E6FFE6);              // Light pastel green background
      end;

    '-': // Deleted Line (Removal)
      begin
        Special := True;
        FG := clMaroon;                     // Text color (FG)
        BG := TColor($E6E6FF);              // Light pastel red/pink background
      end;

    '@': // Hunk Grid Coordinate Separation Metadata
      begin
        Special := True;
        FG := clNavy;                       // Text color (FG)
        BG := TColor($FFF0E6);              // Light pastel blue background
      end;
  end;
end;

procedure TForm1.RefreshUIFromRepo(Repo: TGitRepository);
var
  StatusList: TGitFileStatusArray;
  I: Integer;
  Item: TListItem;
begin
  if not Assigned(Repo) then Exit;

  // 1. Check rebase states
  if Repo.IsRebasing then
    StatusBar1.SimpleText := '⚠️ REBASE IN PROGRESS (Detached HEAD) - Resolve conflicts to continue!'
  else
    StatusBar1.SimpleText := 'Active Branch: ' + Repo.GetActiveBranchName;

  // 2. Populate Status Lists
  StatusList := Repo.GetStatus();
  ListViewStatus.Items.Clear;
  for I := 0 to High(StatusList) do
  begin
    Item := ListViewStatus.Items.Add;
    Item.Caption := StatusList[I].Path;
    Item.SubItems.Add(StatusList[I].State);
  end;

    // 3. POPULATE COMMIT TIMELINE GRAPH DATA
  // We substitute our old history walker with our new unified Graph Array!
  // Mine the repo graph and map the data payload straight into your persistent form field array!
    // --- POPULATE COMMIT HISTORY GRAPH DATA ---
  FGraphList := Repo.GetCommitGraph();

  ListViewHistory.Items.Clear;
  for I := 0 to High(FGraphList) do
  begin
    Item := ListViewHistory.Items.Add;

    // Column 0 is our blank canvas space!
    Item.Caption := '';

    // 👈 FIXED: Extract the data for each column separately into the SubItems array!
    Item.SubItems.Add(FGraphList[I].Message);   // Column 1
    Item.SubItems.Add(FGraphList[I].Author);    // Column 2
    Item.SubItems.Add(DateTimeToStr(FGraphList[I].Timestamp)); // Column 3

    // Debug info row mapping
    if Length(FGraphList[I].ParentIds) = 0 then
      Item.SubItems.Add('[Root Commit]')
    else if Length(FGraphList[I].ParentIds) = 1 then
      Item.SubItems.Add('Parent: ' + Copy(FGraphList[I].ParentIds[0], 1, 7))
    else if Length(FGraphList[I].ParentIds) >= 2 then
      Item.SubItems.Add('Merge: ' + Copy(FGraphList[I].ParentIds[0], 1, 7) + ' + ' + Copy(FGraphList[I].ParentIds[1], 1, 7))
    else
      Item.SubItems.Add('[Orphan State]');
  end;


  // 4. Update Dropdowns and Identity entries
  ComboRemotes.Items.Assign(Repo.GetRemotesList);
  if ComboRemotes.Items.Count > 0 then ComboRemotes.ItemIndex := 0;

  ComboBranches.Items.Assign(Repo.GetLocalBranchesList);
  I := ComboBranches.Items.IndexOf(Repo.GetActiveBranchName);
  if I >= 0 then ComboBranches.ItemIndex := I
  else if ComboBranches.Items.Count > 0 then ComboBranches.ItemIndex := 0;

  EditUserName.Text := Repo.DefaultAuthorName;
  EditUserEmail.Text := Repo.DefaultAuthorEmail;
end;

end.

