{$include compilers.inc}
{$IFDEF COMPILER_16_UP}
  {$WEAKLINKRTTI ON}
  {.$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$ENDIF}
{$IMAGEBASE $13200000}
library actman;
{%ToDo 'actman.todo'}
{%File 'm_actions.inc'}
{%File 'm_actman.inc'}
{%File 'i_const.inc'}
{%File 'i_opt_dlg2.inc'}
{%File 'i_opt_dlg.inc'}
{%File 'i_options.inc'}
{%File 'i_services.inc'}
{%File 'i_vars.inc'}
{%File 'i_inoutxm.inc'}
{%File 'tasks\i_opt_dlg.inc'}
{%File 'tasks\i_options.inc'}
{%File 'tasks\i_task.inc'}
{%File 'hooks\i_options.inc'}
{%File 'hooks\i_hook.inc'}
{%File 'hooks\i_opt_dlg.inc'}
{%File 'ua\i_opt_dlg.inc'}
{%File 'ua\i_inoutxm.inc'}
{%File 'ua\i_options.inc'}
{%File 'ua\i_ua.inc'}
{%File 'ua\i_uaplaces.inc'}
{%File 'ua\i_uconst.inc'}

uses
  m_api,
  Windows,
  messages,
  commctrl,
  common,
  wrapper,
  io,
  dbsettings,
  mirutils,
  syswin,
  base64,
  question,
  mApiCardM,
  global,
  lowlevel,
  iac_global,
  iac_messagebox,
//  iac_dbrw,
  iac_service,
  iac_program,
  iac_chain,
  iac_contact,
  sedit,
  strans;
//  ua in 'ua\ua.pas',
//  hooks in 'hooks\hooks.pas',
//  scheduler in 'tasks\scheduler.pas';

{$r options.res}

const
  PluginName  = 'Action Manager';
var
  hHookShutdown,
  onloadhook,
  opthook:cardinal;
  hevaction,hHookChanged,hevinout:cardinal;
  hsel,hinout,hfree,hget,hrun,hrung,hrunp:cardinal;

{.$include m_actions.inc}
{$include m_actman.inc}


function MirandaPluginInfoEx(mirandaVersion:DWORD):PPLUGININFOEX; cdecl;
begin
  result:=@PluginInfo;
  PluginInfo.cbSize     :=SizeOf(TPLUGININFOEX);
  PluginInfo.shortName  :='Action manager';
  PluginInfo.version    :=$00030001;
  PluginInfo.description:='Plugin for manage hotkeys to open contact window, insert text, '+
                          'run program and call services';
  PluginInfo.author     :='Awkward';
  PluginInfo.authorEmail:='panda75@bk.ru; awk1975@ya.ru';
  PluginInfo.copyright  :='(c) 2007-2012 Awkward';
  PluginInfo.homepage   :='http://code.google.com/p/delphi-miranda-plugins/';
  PluginInfo.flags      :=UNICODE_AWARE;
  PluginInfo.uuid       :=MIID_ACTMAN;
end;

{$include i_const.inc}
{$include i_vars.inc}

{$include i_options.inc}
{$include i_opt_dlg.inc}
{.$include i_inoutxm.inc}
{$include i_services.inc}

function PreShutdown(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  ptr:pActionLink;
begin
  result:=0;

  ptr:=ActionLink;
  while ptr<>nil do
  begin
    if @ptr^.DeInit<>nil then
      ptr^.DeInit;
    ptr:=ptr^.Next;
  end;

  FreeMacroList;

  UnhookEvent(hHookShutdown);
  UnhookEvent(opthook);

  DestroyHookableEvent(hHookChanged);
  DestroyHookableEvent(hevinout);
  DestroyHookableEvent(hevaction);

  DestroyServiceFunction(hfree);
  DestroyServiceFunction(hget);
  DestroyServiceFunction(hrun);
  DestroyServiceFunction(hrung);
  DestroyServiceFunction(hrunp);
  DestroyServiceFunction(hinout);
  DestroyServiceFunction(hsel);
end;

procedure RegisterActTypes;
var
  p:pActModule;
begin
  p:=ModuleLink;
  while p<>nil do
  begin
    p^.Hash:=Hash(p^.Name,StrLen(p^.Name));
    p:=p^.Next;
  end;
end;

function OnModulesLoaded(wParam:WPARAM;lParam:LPARAM):int;cdecl;
var
  ptr:pActionLink;
begin
  Result:=0;
  UnhookEvent(onloadhook);

  RegisterActTypes;

  LoadMacros;
//!!  RegisterIcons;
  
//!!  opthook      :=HookEvent(ME_OPT_INITIALISE ,@OnOptInitialise);
  hHookShutdown:=HookEvent(ME_SYSTEM_SHUTDOWN{ME_SYSTEM_OKTOEXIT},@PreShutdown);
  NotifyEventHooks(hHookChanged,twparam(ACTM_LOADED),0);

  //----- DBEDITOR support -----
//  CallService(MS_DBEDIT_REGISTERSINGLEMODULE,twparam(PluginShort),0);

  IsMultiThread:=true;
  // Load additional modules
  ptr:=ActionLink;
  while ptr<>nil do
  begin
    if @ptr^.Init<>nil then
      ptr^.Init;
    ptr:=ptr^.Next;
  end;

  CallService(MS_ACT_RUNBYNAME,TWPARAM(AutoStartName),0);
end;

function Load():int; cdecl;
begin
  Result:=0;
  Langpack_register;

  hHookChanged:=CreateHookableEvent(ME_ACT_CHANGED);
  hevinout    :=CreateHookableEvent(ME_ACT_INOUT);
  hevaction   :=CreateHookableEvent(ME_ACT_ACTION);

  hfree :=CreateServiceFunction(MS_ACT_FREELIST ,@ActFreeList);
  hget  :=CreateServiceFunction(MS_ACT_GETLIST  ,@ActGetList);
  hrun  :=CreateServiceFunction(MS_ACT_RUNBYID  ,@ActRun);
  hrung :=CreateServiceFunction(MS_ACT_RUNBYNAME,@ActRunGroup);
  hrunp :=CreateServiceFunction(MS_ACT_RUNPARAMS,@ActRunParam);
//!!  hinout:=CreateServiceFunction(MS_ACT_INOUT    ,@ActInOut);
  hsel  :=CreateServiceFunction(MS_ACT_SELECT   ,@ActSelect);

  onloadhook:=HookEvent(ME_SYSTEM_MODULESLOADED,@OnModulesLoaded);
end;

function Unload: int; cdecl;
begin
  Result:=0;
end;

exports
  Load, Unload,
  MirandaPluginInfoEx;

end.
