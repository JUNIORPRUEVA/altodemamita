#define MyAppName "Alto de Mamita App Owner"
#define MyAppSlug "AltoDeMamita_AppOwner"

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0+1"
#endif

#ifndef MyAppVersionInfo
  #define MyAppVersionInfo "1.0.0.1"
#endif

#define MyAppVersionFile StringChange(MyAppVersion, "+", "_")
#define MyAppPublisher "Alto de Mamita"
#define MyAppExeName "sistema_solares_owner.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"
#define BrandSetupIcon "..\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{8B86553A-D6BC-45CE-9C82-3B6DA4B82C59}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename={#MyAppSlug}_Setup_{#MyAppVersionFile}
SetupIconFile={#BrandSetupIcon}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
MinVersion=10.0
SetupLogging=yes
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersionInfo}

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Iconos:"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib,*.bak.*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Abrir carpeta de instalacion"; Filename: "{app}"; WorkingDir: "{app}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function IsInstalledByDisplayName(const DisplayNamePart: string): Boolean;
var
  SubKeys: TArrayOfString;
  I: Integer;
  KeyName: string;
  DisplayName: string;
begin
  Result := False;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;
end;

function FileExistsInSystemDirs(const FileName: string): Boolean;
var
  P: string;
begin
  P := ExpandConstant('{sys}\' + FileName);
  Result := FileExists(P);

  if (not Result) and IsWin64 then
  begin
    P := ExpandConstant('{sysnative}\' + FileName);
    Result := FileExists(P);
  end;
end;

function VcRuntimeFilesPresent(): Boolean;
begin
  Result :=
    FileExistsInSystemDirs('VCRUNTIME140.dll') and
    FileExistsInSystemDirs('VCRUNTIME140_1.dll') and
    FileExistsInSystemDirs('MSVCP140.dll');
end;

function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
begin
  if not VcRuntimeFilesPresent() then
  begin
    Result := True;
    Exit;
  end;

  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    Result := Installed <> 1;
    Exit;
  end;

  Result := not IsInstalledByDisplayName('Microsoft Visual C++ 2015-2022 Redistributable (x64)');
end;

procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel1.Caption := 'Bienvenido a ' + ExpandConstant('{#MyAppName}');
  WizardForm.WelcomeLabel2.Caption :=
    'Este asistente instalara ' + ExpandConstant('{#MyAppName}') + ' en su computadora.' + #13#10#13#10 +
    'Haga clic en "Siguiente" para continuar.';
end;
