; Windows installer, built by the release workflow:
;   iscc /DAppVersion=1.6.0 /O<output dir> windows\installer\anigen.iss
; after `flutter build windows --release`. Paths are relative to this file.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Keep this id: it's how a new version replaces the installed one
AppId={{AD2A8019-557C-48D6-A238-59735300970B}
AppName=Anigen
AppVersion={#AppVersion}
AppVerName=Anigen {#AppVersion}
AppPublisher=Anigen
AppPublisherURL=https://github.com/ruck-syu/Anigen
DefaultDirName={autopf}\Anigen
DefaultGroupName=Anigen
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\anigen.exe
OutputBaseFilename=Anigen-v{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Anigen"; Filename: "{app}\anigen.exe"
Name: "{autodesktop}\Anigen"; Filename: "{app}\anigen.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\anigen.exe"; Description: "{cm:LaunchProgram,Anigen}"; Flags: nowait postinstall skipifsilent
