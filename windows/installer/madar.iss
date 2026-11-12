; Inno Setup script — يبني مثبّت madar-setup.exe من ناتج
; `flutter build windows --release -t lib/main_desktop.dart`.
; بيتشغل من CI (windows-latest عنده Inno Setup مثبّت جاهز)، أو محليًا
; على ويندوز بعد تثبيت Inno Setup 6: iscc windows\installer\madar.iss

#define MyAppName "Madar"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Madar"
#define MyAppExeName "madar.exe"

[Setup]
AppId={{2B9F0C2E-7C3B-4C0E-9E7D-9B2B6E4D1A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\installer_output
OutputBaseFilename=madar-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
