package main

import (
	"fmt"
	"runtime"
)

// appVersion is the POC application version reported to the UI.
const appVersion = "0.1.0"

// SkillManagerService exposes the Skill Manager POC operations to the frontend.
//
// IMPORTANT: This is a build/distribution feasibility POC. None of these methods
// perform real skill operations. They only return dummy data or dummy success
// messages. There is deliberately no real install, publish, Git, Nexus, auth,
// PAT handling, auto-update, or assistant detection here.
type SkillManagerService struct{}

// RuntimeInfo describes the host environment and backend status for the info panel.
type RuntimeInfo struct {
	OS            string `json:"os"`
	Arch          string `json:"arch"`
	AppVersion    string `json:"appVersion"`
	GoVersion     string `json:"goVersion"`
	BackendStatus string `json:"backendStatus"`
}

// Assistant is a dummy AI assistant target.
type Assistant struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Role is a dummy role preset. SkillIDs are the skills the preset selects.
type Role struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	SkillIDs []string `json:"skillIDs"`
}

// Skill is a dummy skill entry.
type Skill struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// dummySkills is the fixed, fake catalogue used everywhere in this POC.
var dummySkills = []Skill{
	{ID: "java-code-review", Name: "Java Code Review", Description: "Dummy skill: reviews Java code."},
	{ID: "sql-analysis", Name: "SQL Analysis", Description: "Dummy skill: analyses SQL queries."},
	{ID: "openapi-review", Name: "OpenAPI Review", Description: "Dummy skill: reviews OpenAPI specs."},
	{ID: "requirements-review", Name: "Requirements Review", Description: "Dummy skill: reviews requirements."},
}

// GetRuntimeInfo returns dummy/real runtime metadata for the info panel.
// OS, Arch and GoVersion are real (cheap to read); the rest is POC scaffolding.
func (s *SkillManagerService) GetRuntimeInfo() RuntimeInfo {
	return RuntimeInfo{
		OS:            runtime.GOOS,
		Arch:          runtime.GOARCH,
		AppVersion:    appVersion,
		GoVersion:     runtime.Version(),
		BackendStatus: "OK — Go backend reachable via Wails",
	}
}

// ListAssistants returns the dummy assistant selector options.
func (s *SkillManagerService) ListAssistants() []Assistant {
	return []Assistant{
		{ID: "claude-code", Name: "Claude Code"},
		{ID: "opencode", Name: "OpenCode"},
		{ID: "cursor", Name: "Cursor"},
	}
}

// ListRoles returns the dummy role presets. Each preset maps to a set of skills.
// "Select All" is intentionally handled in the frontend, not as a backend role.
func (s *SkillManagerService) ListRoles() []Role {
	return []Role{
		{ID: "backend-engineer", Name: "Back-end Engineer", SkillIDs: []string{"java-code-review", "sql-analysis"}},
		{ID: "ui-engineer", Name: "UI Engineer", SkillIDs: []string{"openapi-review"}},
		{ID: "fullstack-engineer", Name: "Full-stack Engineer", SkillIDs: []string{"java-code-review", "sql-analysis", "openapi-review"}},
		{ID: "business-analyst", Name: "Business Analyst", SkillIDs: []string{"requirements-review"}},
	}
}

// ListSkills returns the dummy skills list.
func (s *SkillManagerService) ListSkills() []Skill {
	return dummySkills
}

// InstallSkill pretends to install a skill. POC only.
func (s *SkillManagerService) InstallSkill(skillID string) string {
	return pocResult("Install", skillID)
}

// UpdateSkill pretends to update a skill. POC only.
func (s *SkillManagerService) UpdateSkill(skillID string) string {
	return pocResult("Update", skillID)
}

// DeleteSkill pretends to delete a skill. POC only.
func (s *SkillManagerService) DeleteSkill(skillID string) string {
	return pocResult("Delete", skillID)
}

// pocResult builds a dummy success message for a fake operation.
func pocResult(action, skillID string) string {
	name := skillName(skillID)
	return fmt.Sprintf("%s %q (%s): POC only — no real skill operation performed.", action, name, skillID)
}

// skillName resolves a skill ID to its display name, falling back to the ID.
func skillName(skillID string) string {
	for _, sk := range dummySkills {
		if sk.ID == skillID {
			return sk.Name
		}
	}
	return skillID
}
