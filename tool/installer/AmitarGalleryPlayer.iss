#ifndef BuildRoot
  #define BuildRoot "..\..\build\windows\x64\runner\Release"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef ProjectRoot
  #define ProjectRoot "..\.."
#endif

#define AppName "AmitarGalleryPlayer"
#define AppExeName "amitar_gallery_player.exe"

[Setup]
AppId={{9CBACB29-5C48-4B90-9A6C-43D7D45F8D12}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Seyed Amir Mohammad Emami
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=AmitarGalleryPlayer-Setup-Windows
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#ProjectRoot}\assets\icons\app-icon.ico
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
