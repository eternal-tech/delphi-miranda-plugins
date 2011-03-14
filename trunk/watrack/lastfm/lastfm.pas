unit lastfm;
{$include compilers.inc}
interface
{$Resource lastfm.res}
implementation

uses windows, messages, commctrl,
  common,
  m_api,dbsettings,swrapper,mirutils,
  wat_api,global;

const
  opt_ModStatus:PAnsiChar = 'module/lastfm';
const
  IcoLastFM:pAnsiChar = 'WATrack_lasfm';
var
  md5:TMD5_INTERFACE;
  lfm_tries:integer;
  sic:THANDLE;
  slastinf:THANDLE;
  slast:THANDLE;
const
  lfm_lang    :integer=0;
  lfm_on      :integer=0;
  hMenuLast   :HMENU = 0;
  lfm_login   :pAnsiChar=nil;
  lfm_password:pAnsiChar=nil;
  session_id  :pAnsiChar=nil;
  np_url      :pAnsiChar=nil;
  sub_url     :pAnsiChar=nil;

function GetModStatus:integer;
begin
  result:=DBReadByte(0,PluginShort,opt_ModStatus,1);
end;

procedure SetModStatus(stat:integer);
begin
  DBWriteByte(0,PluginShort,opt_modStatus,stat);
end;

{$i i_const.inc}
{$i i_last_opt.inc}
{$i i_last_api.inc}

function ThScrobble(param:LPARAM):dword; //stdcall;
var
  count:integer;
  npisok:bool;
begin
  count:=lfm_tries;
  npisok:=false;
  while count>0 do
  begin
    if not npisok then
      npisok:=SendNowPlaying>=0;
    if Scrobble>=0 then break;
    HandShake(lfm_login,lfm_password, count=1); // just last time
    dec(count);
  end;
  if count=0 then ;
  result:=0;
end;

const
  hTimer:THANDLE=0;

procedure TimerProc(wnd:HWND;uMsg:cardinal;idEvent:cardinal;dwTime:dword); stdcall;
var
  res:uint_ptr;
begin
  if hTimer<>0 then
  begin
    KillTimer(0,hTimer);
    hTimer:=0;
  end;

  if (lfm_login   <>nil) and (lfm_login^   <>#0) and
     (lfm_password<>nil) and (lfm_password^<>#0) then
    CloseHandle(BeginThread(nil,0,@ThScrobble,nil,0,res));
end;

function NewPlStatus(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  flag:integer;
  mi:TCListMenuItem;
begin
  result:=0;
  case wParam of
    WAT_EVENT_NEWTRACK: begin
      if hTimer<>0 then
        KillTimer(0,hTimer);
      if lfm_on=0 then
        hTimer:=SetTimer(0,0,30000,@TimerProc)
    end;

    WAT_EVENT_PLUGINSTATUS: begin
      case lParam of
        dsEnabled: begin
          lfm_on:=lfm_on and not 2;
          flag:=0;
        end;
        dsPermanent: begin
          lfm_on:=lfm_on or 2;
          if hTimer<>0 then
          begin
            KillTimer(0,hTimer);
            hTimer:=0;
          end;
          flag:=CMIF_GRAYED;
        end;
      else // like 1
        exit
      end;
      FillChar(mi,sizeof(mi),0);
      mi.cbSize:=sizeof(mi);
      mi.flags :=CMIM_FLAGS+flag;
      CallService(MS_CLIST_MODIFYMENUITEM,hMenuLast,dword(@mi));
    end;
    
    WAT_EVENT_PLAYERSTATUS: begin
      case Integer(loword(lParam)) of
        WAT_PLS_NOMUSIC,WAT_PLS_NOTFOUND: begin
          if hTimer<>0 then
          begin
            KillTimer(0,hTimer);
            hTimer:=0;
          end;
        end;
      end;
    end;
  end;
end;

{$i i_last_dlg.inc}

function IconChanged(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  mi:TCListMenuItem;
begin
  result:=0;
  FillChar(mi,SizeOf(mi),0);
  mi.cbSize:=sizeof(mi);
  mi.flags :=CMIM_ICON;
  mi.hIcon :=PluginLink^.CallService(MS_SKIN2_GETICON,0,dword(IcoLastFM));
  CallService(MS_CLIST_MODIFYMENUITEM,hMenuLast,dword(@mi));
end;

function SrvLastFMInfo(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  data:tLastFMInfo;
begin
  case wParam of
    0: result:=GetArtistInfo(data,lParam);
    1: result:=GetAlbumInfo (data,lParam);
    2: result:=GetTrackInfo (data,lParam);
  else
    result:=0;
  end;
end;

function SrvLastFM(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  mi:TCListMenuItem;
begin
  FillChar(mi,sizeof(mi),0);
  mi.cbSize:=sizeof(mi);
  mi.flags :=CMIM_NAME;
  if odd(lfm_on) then
  begin
    mi.szName.a:='Disable scrobbling';
    lfm_on:=lfm_on and not 1;
  end
  else
  begin
    mi.szName.a:='Enable scrobbling';
    lfm_on:=lfm_on or 1;
    if hTimer<>0 then
    begin
      KillTimer(0,hTimer);
      hTimer:=0;
    end;
  end;
  CallService(MS_CLIST_MODIFYMENUITEM,hMenuLast,dword(@mi));
  result:=ord(not odd(lfm_on));
end;

procedure CreateMenus;
var
  mi:TCListMenuItem;
  sid:TSKINICONDESC;
begin
  FillChar(sid,SizeOf(TSKINICONDESC),0);
  sid.cbSize:=SizeOf(TSKINICONDESC);
  sid.cx:=16;
  sid.cy:=16;
  sid.szSection.a:='WATrack';

  sid.hDefaultIcon   :=LoadImage(hInstance,MAKEINTRESOURCE(IDI_LAST),IMAGE_ICON,16,16,0);
  sid.pszName        :=IcoLastFM;
  sid.szDescription.a:='LastFM';
  PluginLink^.CallService(MS_SKIN2_ADDICON,0,dword(@sid));
  DestroyIcon(sid.hDefaultIcon);
  
  FillChar(mi, sizeof(mi), 0);
  mi.cbSize       :=sizeof(mi);
  mi.szPopupName.a:=PluginShort;

  mi.hIcon        :=PluginLink^.CallService(MS_SKIN2_GETICON,0,dword(IcoLastFM));
  mi.szName.a     :='Disable scrobbling';
  mi.pszService   :=MS_WAT_LASTFM;
  mi.popupPosition:=500050000;
  hMenuLast:=PluginLink^.CallService(MS_CLIST_ADDMAINMENUITEM,0,dword(@mi));
end;

// ------------ base interface functions -------------

function AddOptionsPage(var tmpl:pAnsiChar;var proc:pointer;var name:PAnsiChar):integer;
begin
  tmpl:='LASTFM';
  proc:=@DlgProcOptions;
  name:='LastFM';
  result:=0;
end;

var
  plStatusHook:THANDLE;

function InitProc(aGetStatus:boolean=false):integer;
begin
  slastinf:=PluginLink^.CreateServiceFunction(MS_WAT_LASTFMInfo,@SrvLastFMInfo);
  if aGetStatus then
  begin
    if GetModStatus=0 then
    begin
      result:=0;
      exit;
    end;
  end
  else
  begin
    SetModStatus(1);
    lfm_on:=lfm_on and not 4;
  end;
  result:=1;

  LoadOpt;

  if md5.cbSize=0 then
  begin
    md5.cbSize:=SizeOf(TMD5_INTERFACE);
    if (CallService(MS_SYSTEM_GET_MD5I,0,dword(@md5))<>0) then
    begin
    end;
  end;

  slast:=PluginLink^.CreateServiceFunction(MS_WAT_LASTFM,@SrvLastFM);
  if hMenuLast=0 then
    CreateMenus;
  sic:=PluginLink^.HookEvent(ME_SKIN2_ICONSCHANGED,@IconChanged);
  if (lfm_on and 4)=0 then
    plStatusHook:=PluginLink^.HookEvent(ME_WAT_NEWSTATUS,@NewPlStatus);
end;

procedure DeInitProc(aSetDisable:boolean);
begin
  if aSetDisable then
    SetModStatus(0)
  else
    PluginLink^.DestroyServiceFunction(slastinf);

  PluginLink^.DestroyServiceFunction(slast);
  PluginLink^.UnhookEvent(plStatusHook);
  PluginLink^.UnhookEvent(sic);

  if hTimer<>0 then
  begin
    KillTimer(0,hTimer);
    hTimer:=0;
  end;

  FreeOpt;

  mFreeMem(session_id);
  mFreeMem(np_url);
  mFreeMem(sub_url);

  lfm_on:=lfm_on or 4;
end;

var
  last:twModule;

procedure Init;
begin
  last.Next      :=ModuleLink;
  last.Init      :=@InitProc;
  last.DeInit    :=@DeInitProc;
  last.AddOption:=@AddOptionsPage;
  last.ModuleName:='Last.FM';
  ModuleLink     :=@last;

  md5.cbSize:=0;
end;

begin
  Init;
end.
