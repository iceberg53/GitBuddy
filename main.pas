unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
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
    procedure ListViewStatusSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure SynEditDiffPaint(Sender: TObject; ACanvas: TCanvas);
    procedure SynEditDiffSpecialLineColors(Sender: TObject; Line: integer;
      var Special: boolean; var FG, BG: TColor);
  private
    FSessionToken: string; // Stores the Personal Access Token in RAM for this session
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
begin
  if SelectDirectoryDialog1.Execute then
  begin
    EditRepoPath.Text := SelectDirectoryDialog1.FileName;
  end;
end;

procedure TForm1.BtnValidateClick(Sender: TObject);
var
  Repo: TGitRepository;
  StatusList: TGitFileStatusArray;
  HistoryList: TGitCommitHistoryArray;
  I: Integer;
  Item: TListItem;
begin
  if EditRepoPath.Text = '' then Exit;

  try
    Repo := TGitRepository.Open(EditRepoPath.Text);

    try
      // 1.1. Check if the workspace is locked in an unfinished transaction
      if Repo.IsRebasing then
      begin
        StatusBar1.SimpleText := '⚠️ REBASE IN PROGRESS (Detached HEAD) - Resolve conflicts to continue!';

        BtnRebaseContinue.Enabled := True;
        BtnRebaseAbort.Enabled := True;
        BtnCommit.Enabled := False;
        BtnRebaseBranch.Enabled := False;
      end
      else
      begin
        StatusBar1.SimpleText := 'Active Branch: ' + Repo.GetActiveBranchName;

        BtnRebaseContinue.Enabled := False;
        BtnRebaseAbort.Enabled := False;
        BtnCommit.Enabled := True;
        BtnRebaseBranch.Enabled := True;
      end;

      // 1.2. Fetch the updated status array maps (now containing your conflicted files!)
      StatusList := Repo.GetStatus();
      ListViewStatus.Items.Clear;
      for I := 0 to High(StatusList) do
      begin
        Item := ListViewStatus.Items.Add;
        Item.Caption := StatusList[I].Path;
        Item.SubItems.Add(StatusList[I].State);
      end;

      // ----------------------------------------------------
      // 2. POPULATE COMMIT TIMELINE GRID (Left Side)
      // ----------------------------------------------------
      HistoryList := Repo.GetCommitHistory();
      ListViewHistory.Items.Clear;
      for I := 0 to High(HistoryList) do
      begin
        Item := ListViewHistory.Items.Add;
        Item.Caption := HistoryList[I].Message;
        Item.SubItems.Add(HistoryList[I].Author);
        Item.SubItems.Add(DateTimeToStr(HistoryList[I].Timestamp));
      end;

      // --- REFRESH REMOTE TARGET OPTIONS ---
      ComboRemotes.Items.Assign(Repo.GetRemotesList);
      if ComboRemotes.Items.Count > 0 then
        ComboRemotes.ItemIndex := 0;

      // --- OPTIMIZED BRANCH LIST REFRESH ---
      // Only rebuild the list array if a branch was added/deleted to prevent UI flickering
      if ComboBranches.Items.Count <> Repo.GetLocalBranchesList.Count then
      begin
        ComboBranches.Items.Assign(Repo.GetLocalBranchesList);
      end;

      // Keep the visual selection perfectly synced with actual HEAD on disk
      I := ComboBranches.Items.IndexOf(Repo.GetActiveBranchName);
      if I >= 0 then
      begin
        ComboBranches.ItemIndex := I;
      end;

      // --- SYNC DISCOVERED IDENTITY TO UI FIELDS ---
      EditUserName.Text := Repo.DefaultAuthorName;
      EditUserEmail.Text := Repo.DefaultAuthorEmail;

    finally
      // This block is guaranteed to execute even if code above fails, preventing RAM leaks
      Repo.Free;
    end;

  except
    // 3. THE ERROR CAPTURE: Triggered if any step inside the outer try block fails
    on E: EGitException do
      ShowMessage('Git Subsystem Error: ' + E.Message);
    on E: Exception do
      ShowMessage('Application Error: ' + E.Message);
  end;
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


end.

