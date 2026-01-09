package statusline

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/himattm/prism/internal/config"
)

// TestRenderLinesChanged_NeverUsesClaudeStats verifies that linesChanged
// ALWAYS uses git diff stats and NEVER falls back to Claude's session stats.
// This is critical - we've had bugs where Claude's stats were shown instead.
func TestRenderLinesChanged_NeverUsesClaudeStats(t *testing.T) {
	// Create a temp git repo for testing
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Create a StatusLine with Claude's stats set to non-zero values
	// If the implementation incorrectly uses these, the test will fail
	sl := &StatusLine{
		input: Input{
			Workspace: WorkspaceInfo{
				ProjectDir: tmpDir,
				CurrentDir: tmpDir,
			},
			Cost: CostInfo{
				TotalLinesAdded:   999, // These should NEVER appear in output
				TotalLinesRemoved: 888, // These should NEVER appear in output
			},
		},
		isIdle: false, // Even when not idle, should use git stats
	}

	result := sl.renderLinesChanged()

	// Should show +0 -0 (clean repo), NOT +999 -888 (Claude's stats)
	if strings.Contains(result, "999") || strings.Contains(result, "888") {
		t.Errorf("renderLinesChanged used Claude's stats instead of git stats: %s", result)
	}
	if !strings.Contains(result, "+0") || !strings.Contains(result, "-0") {
		t.Errorf("expected +0 -0 for clean repo, got: %s", result)
	}
}

// TestRenderLinesChanged_WithUncommittedChanges verifies git stats are shown
func TestRenderLinesChanged_WithUncommittedChanges(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Create and stage a new file (git diff HEAD shows staged changes)
	testFile := filepath.Join(tmpDir, "test.txt")
	if err := os.WriteFile(testFile, []byte("line1\nline2\nline3\n"), 0644); err != nil {
		t.Fatal(err)
	}

	// Stage the file so it shows in git diff HEAD
	cmd := exec.Command("git", "add", "test.txt")
	cmd.Dir = tmpDir
	cmd.Run()

	sl := &StatusLine{
		input: Input{
			Workspace: WorkspaceInfo{
				ProjectDir: tmpDir,
			},
			Cost: CostInfo{
				TotalLinesAdded:   0, // Even if Claude says 0
				TotalLinesRemoved: 0, // Git should show the real changes
			},
		},
	}

	result := sl.renderLinesChanged()

	// Should show +3 -0 (3 lines added)
	if !strings.Contains(result, "+3") {
		t.Errorf("expected +3 for 3 added lines, got: %s", result)
	}
}

// TestRenderLinesChanged_IdleStateDoesNotAffectBehavior ensures idle state
// has no impact on which stats are used (always git)
func TestRenderLinesChanged_IdleStateDoesNotAffectBehavior(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Create an uncommitted change
	testFile := filepath.Join(tmpDir, "test.txt")
	os.WriteFile(testFile, []byte("hello\n"), 0644)

	claudeStats := CostInfo{
		TotalLinesAdded:   100,
		TotalLinesRemoved: 50,
	}

	// Test with isIdle = true
	slIdle := &StatusLine{
		input:  Input{Workspace: WorkspaceInfo{ProjectDir: tmpDir}, Cost: claudeStats},
		isIdle: true,
	}
	resultIdle := slIdle.renderLinesChanged()

	// Test with isIdle = false
	slBusy := &StatusLine{
		input:  Input{Workspace: WorkspaceInfo{ProjectDir: tmpDir}, Cost: claudeStats},
		isIdle: false,
	}
	resultBusy := slBusy.renderLinesChanged()

	// Both should show the same git-based stats (+1 -0), not Claude's stats
	if resultIdle != resultBusy {
		t.Errorf("idle state affected linesChanged output:\nidle=%s\nbusy=%s", resultIdle, resultBusy)
	}
	if strings.Contains(resultIdle, "100") || strings.Contains(resultIdle, "50") {
		t.Errorf("Claude's stats were used instead of git stats: %s", resultIdle)
	}
}

// TestGetGitDiffStats_EmptyDir returns 0,0 for empty project dir
func TestGetGitDiffStats_EmptyDir(t *testing.T) {
	added, removed := getGitDiffStats("")
	if added != 0 || removed != 0 {
		t.Errorf("expected 0,0 for empty dir, got %d,%d", added, removed)
	}
}

// TestGetGitDiffStats_NotGitRepo returns 0,0 for non-git directory
func TestGetGitDiffStats_NotGitRepo(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "prism-test-nogit-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	added, removed := getGitDiffStats(tmpDir)
	if added != 0 || removed != 0 {
		t.Errorf("expected 0,0 for non-git dir, got %d,%d", added, removed)
	}
}

// TestGetGitDiffStats_CleanRepo returns 0,0 for clean working tree
func TestGetGitDiffStats_CleanRepo(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	added, removed := getGitDiffStats(tmpDir)
	if added != 0 || removed != 0 {
		t.Errorf("expected 0,0 for clean repo, got %d,%d", added, removed)
	}
}

// TestGetGitDiffStats_WithChanges correctly counts added/removed lines
func TestGetGitDiffStats_WithChanges(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Modify the existing file (adds lines, removes lines)
	readmeFile := filepath.Join(tmpDir, "README.md")
	os.WriteFile(readmeFile, []byte("new content\nline 2\nline 3\n"), 0644)

	added, removed := getGitDiffStats(tmpDir)

	// Original had 1 line ("# Test"), new has 3 lines
	// So we should see additions and the original line removed
	if added == 0 && removed == 0 {
		t.Errorf("expected non-zero changes after modifying file, got +%d -%d", added, removed)
	}
}

// TestGetGitDiffStats_NewUntrackedFile does not count untracked files
func TestGetGitDiffStats_NewUntrackedFile(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Create a new untracked file (not staged)
	newFile := filepath.Join(tmpDir, "untracked.txt")
	os.WriteFile(newFile, []byte("untracked content\n"), 0644)

	added, removed := getGitDiffStats(tmpDir)

	// git diff HEAD doesn't show untracked files
	if added != 0 || removed != 0 {
		t.Errorf("untracked files should not affect diff stats, got +%d -%d", added, removed)
	}
}

// TestGetGitDiffStats_StagedChanges counts staged changes
func TestGetGitDiffStats_StagedChanges(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	// Create and stage a new file
	newFile := filepath.Join(tmpDir, "staged.txt")
	os.WriteFile(newFile, []byte("line1\nline2\n"), 0644)

	cmd := exec.Command("git", "add", "staged.txt")
	cmd.Dir = tmpDir
	cmd.Run()

	added, removed := getGitDiffStats(tmpDir)

	// git diff HEAD shows staged changes
	if added != 2 {
		t.Errorf("expected 2 added lines for staged file, got +%d -%d", added, removed)
	}
}

// TestRenderLinesChanged_OutputFormat verifies the output format
func TestRenderLinesChanged_OutputFormat(t *testing.T) {
	tmpDir := setupTestGitRepo(t)
	defer os.RemoveAll(tmpDir)

	sl := &StatusLine{
		input: Input{Workspace: WorkspaceInfo{ProjectDir: tmpDir}},
	}

	result := sl.renderLinesChanged()

	// Should contain ANSI color codes and +/- format
	if !strings.Contains(result, "\033[32m+") { // Green for additions
		t.Errorf("missing green color for additions: %s", result)
	}
	if !strings.Contains(result, "\033[31m-") { // Red for removals
		t.Errorf("missing red color for removals: %s", result)
	}
}

// setupTestGitRepo creates a temporary git repository for testing
func setupTestGitRepo(t *testing.T) string {
	t.Helper()

	tmpDir, err := os.MkdirTemp("", "prism-test-git-*")
	if err != nil {
		t.Fatal(err)
	}

	// Initialize git repo
	cmds := [][]string{
		{"git", "init"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
	}

	for _, args := range cmds {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = tmpDir
		if err := cmd.Run(); err != nil {
			os.RemoveAll(tmpDir)
			t.Fatalf("failed to run %v: %v", args, err)
		}
	}

	// Create initial commit
	readmeFile := filepath.Join(tmpDir, "README.md")
	if err := os.WriteFile(readmeFile, []byte("# Test\n"), 0644); err != nil {
		os.RemoveAll(tmpDir)
		t.Fatal(err)
	}

	cmd := exec.Command("git", "add", "README.md")
	cmd.Dir = tmpDir
	cmd.Run()

	cmd = exec.Command("git", "commit", "-m", "Initial commit")
	cmd.Dir = tmpDir
	if err := cmd.Run(); err != nil {
		os.RemoveAll(tmpDir)
		t.Fatalf("failed to create initial commit: %v", err)
	}

	return tmpDir
}

// TestNew_CreatesStatusLine verifies the constructor works
func TestNew_CreatesStatusLine(t *testing.T) {
	input := Input{
		SessionID: "test-session",
		Model:     ModelInfo{DisplayName: "Test Model"},
	}
	cfg := config.Config{}

	sl := New(input, cfg)

	if sl == nil {
		t.Fatal("New returned nil")
	}
	if sl.input.SessionID != "test-session" {
		t.Errorf("session ID not set correctly")
	}
}
