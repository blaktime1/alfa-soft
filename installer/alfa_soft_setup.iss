; -----------------------------------------------------------------------------
; ALFA SOFT — INNO SETUP 6 PRODUCTION COMPILER SCRIPT
; Native Windows C++ Flutter Desktop Offline ERP & POS System
; -----------------------------------------------------------------------------

#define MyAppName "ALFA SOFT ERP & POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "ALFA SOFT Enterprise Solutions"
#define MyAppURL "https://alfasoft.local"
#define MyAppExeName "alfa_soft.exe"
#define SourceOutputDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{5E973B1B-622E-4D3B-A882-7301BC4C3814}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\AlfaSoft
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE.txt
OutputDir=..\dist
OutputBaseFilename=AlfaSoft-Setup-1.0.0-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
DisableDirPage=no

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupicon"; Description: "تشغيل النظام تلقائياً عند بدء تشغيل ويندوز (Launch on Windows Startup)"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main Executable and Flutter Desktop runtime
Source: "{#SourceOutputDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceOutputDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceOutputDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Filename: "{app}\{#MyAppExeName}"; Flags: nowait postinstall skipifsilent

[Code]
// Custom Inno Setup Pascal Scripting for Pre-requisite checks
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
