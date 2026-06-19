package main

import (
	"embed"
	"log"

	"github.com/wailsapp/wails/v3/pkg/application"
)

// Wails uses Go's `embed` package to embed the frontend files into the binary.
// Any files in the frontend/dist folder will be embedded into the binary and
// made available to the frontend at runtime. This is what removes the Node/NPM
// requirement for end users: Node is only needed at build time to produce dist.
//
//go:embed all:frontend/dist
var assets embed.FS

// main is the application entry point. It creates the Wails application, binds
// the dummy SkillManagerService so the React frontend can call Go methods, and
// opens a single window.
func main() {
	app := application.New(application.Options{
		Name:        "Skill Manager POC",
		Description: "Build/distribution feasibility POC for Wails v3 + Go + React. No real Skill Manager functionality.",
		Services: []application.Service{
			application.NewService(&SkillManagerService{}),
		},
		Assets: application.AssetOptions{
			Handler: application.AssetFileServerFS(assets),
		},
		Mac: application.MacOptions{
			ApplicationShouldTerminateAfterLastWindowClosed: true,
		},
	})

	app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title:  "Skill Manager POC",
		Width:  1000,
		Height: 800,
		Mac: application.MacWindow{
			InvisibleTitleBarHeight: 50,
			Backdrop:                application.MacBackdropTranslucent,
			TitleBar:                application.MacTitleBarHiddenInset,
		},
		BackgroundColour: application.NewRGB(27, 38, 54),
		URL:              "/",
	})

	if err := app.Run(); err != nil {
		log.Fatal(err)
	}
}
