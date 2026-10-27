; Inno Setup script for Statera. Build: ISCC /DAppVersion=0.1.0 installer\windows\statera.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8C1B8F4E-7A55-4C0E-9C2E-5A1D7F3B9E11}
AppName=Statera
AppVersion={#AppVersion}
AppVerName=Statera {#AppVersion}
AppPublisher=Risso Productions
AppPublisherURL=https://github.com/NicolasRisso/OpenSPSS
DefaultDirName={autopf}\Statera
DefaultGroupName=Statera
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=Statera-v{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\assets\icon\statera.ico
UninstallDisplayIcon={app}\statera.exe
LicenseFile=..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
ChangesAssociations=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "assoc"; Description: "Open .sav files with Statera"

[Files]
Source: "..\..\build\statera.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\SDL3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"

[Icons]
Name: "{autoprograms}\Statera"; Filename: "{app}\statera.exe"
Name: "{autodesktop}\Statera"; Filename: "{app}\statera.exe"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\.sav\OpenWithProgids"; ValueType: string; ValueName: "Statera.sav"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\Statera.sav"; ValueType: string; ValueName: ""; ValueData: "SPSS data file"; Flags: uninsdeletekey; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\Statera.sav\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\statera.exe,0"; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\Statera.sav\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\statera.exe"" ""%1"""; Tasks: assoc

[Run]
Filename: "{app}\statera.exe"; Description: "Launch Statera"; Flags: nowait postinstall skipifsilent
