# dev.ps1 - Start BiMusic development environment
# Opens backend (npm run dev) and Flutter Windows app as new tabs in Windows Terminal

$rootDir = $PSScriptRoot

wt --window 0 new-tab --title "BiMusic Backend" --startingDirectory "$rootDir\backend" powershell.exe -NoExit -Command "npm run dev"

wt --window 0 new-tab --title "BiMusic Flutter" --startingDirectory "$rootDir\bimusic_app" powershell.exe -NoExit -Command 'flutter run -d windows'
