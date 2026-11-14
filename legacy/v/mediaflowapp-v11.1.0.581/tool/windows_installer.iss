; Inno Setup script for the MediaFlow Windows installer.
; Built in CI: ISCC /DAppVersion=<version> /DSourceDir=<Release folder> /DOutputDir=<dist> /DIconFile=<app_icon.ico> tool\windows_installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6F1C6C2-6E1E-4C7A-9F0B-2C5D4B8B5A11}
AppName=MediaFlow
AppVersion={#AppVersion}
AppPublisher=Alex Godly
DefaultDirName={autopf}\MediaFlow
DefaultGroupName=MediaFlow
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=MediaFlow-{#AppVersion}-Windows-x64-Setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\MediaFlow.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\MediaFlow"; Filename: "{app}\MediaFlow.exe"
Name: "{autodesktop}\MediaFlow"; Filename: "{app}\MediaFlow.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MediaFlow.exe"; Description: "Open MediaFlow"; Flags: nowait postinstall skipifsilent
