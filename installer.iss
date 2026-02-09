#define MyAppName "Anigen"
#define MyAppVersion "1.5"
#define MyAppExeName "anigen.exe"

[Setup]
AppId={{B1B6A1C8-8C0D-4E7A-A111-123456789ABC}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=installer
OutputBaseFilename=Setup
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\runner\Release*"; DestDir: "{app}"; Flags: recursesubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"

[Icons]
Name: "{group}{#MyAppName}"; Filename: "{app}{#MyAppExeName}"
Name: "{commondesktop}{#MyAppName}"; Filename: "{app}{#MyAppExeName}"

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /passive /norestart"; Flags: waituntilterminated
Filename: "{app}{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

