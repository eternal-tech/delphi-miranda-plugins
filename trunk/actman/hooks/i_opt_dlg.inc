{}
const
  settings:HWND = 0;
var
  OldTableProc:pointer;
  onactchanged:THANDLE;

const
  ACI_NEW    :PAnsiChar = 'ACI_New';
  ACI_DELETE :PAnsiChar = 'ACI_Delete';

procedure CheckHookList(wnd:HWND);
var
  i:integer;
  li:LV_ITEMW;
  arr:array [0..127] of WideChar;
begin
  ClearHooks;

  li.mask      :=LVIF_TEXT or LVIF_PARAM;
  li.pszText   :=@arr;
  li.cchTextMax:=SizeOf(arr) div SizeOf(WideChar);

  MaxHooks:=SendMessage(wnd,LVM_GETITEMCOUNT,0,0);
  
  GetMem  (HookList ,MaxHooks*SizeOf(tHookRec));
  FillChar(HookList^,MaxHooks*SizeOf(tHookRec),0);
  for i:=0 to MaxHooks-1 do
  begin
    with HookList[i] do
    begin
      flags:=ACF_ASSIGNED;
      li.iItem   :=i;
      li.iSubItem:=0;
      SendMessageW(wnd,LVM_GETITEMW,0,LPARAM(@li));
      StrDupW(descr,arr);
      action:=li.lParam;
      li.iSubItem:=1;
      SendMessageA(wnd,LVM_GETITEMA,0,LPARAM(@li));
      StrDup(name,pAnsiChar(@arr));

      if ListView_GetCheckState(wnd,i)=0 then // disabled
        flags:=flags or ACF_DISABLED;
    end;
  end;
end;

procedure FillHookList(wnd:HWND);
var
  i:integer;
  li:LV_ITEMW;
begin
  SendMessage(wnd,LVM_DELETEALLITEMS,0,0);
  for i:=0 to MaxHooks-1 do
  begin
    with HookList[i] do
    begin
      if (flags and ACF_ASSIGNED)<>0 then
      begin
        li.mask    :=LVIF_TEXT+LVIF_PARAM;
        li.iSubItem:=0;
        li.iItem   :=i;
        li.lParam  :=action;
        li.pszText :=descr;
        li.iItem   :=SendMessageW(wnd,LVM_INSERTITEMW,0,LPARAM(@li));
        li.mask    :=LVIF_TEXT;
        li.iSubItem:=1;
        li.pszText :=pWideChar(name);
        SendMessageA(wnd,LVM_SETITEMA,0,LPARAM(@li));
        ListView_SetCheckState(wnd,li.iItem,(flags and ACF_DISABLED)=0);
      end;
    end;
  end;
  ListView_SetItemState(wnd,0,
    LVIS_FOCUSED or LVIS_SELECTED,
    LVIS_FOCUSED or LVIS_SELECTED);
end;

procedure FillEventList(wnd:HWND);
var
  buf:array [0..8191] of AnsiChar;
  p:PAnsiChar;
begin
  SendMessage(wnd,CB_RESETCONTENT,0,0);

  buf[0]:=#0;
  GetPrivateProfileSectionNamesA(buf,SizeOf(buf),'plugins\events.ini'); // sections
  p:=@buf;
  while p^<>#0 do
  begin
    SendMessageA(wnd,CB_ADDSTRING,0,lparam(p));
    while p^<>#0 do inc(p); inc(p);
  end;

  SendMessage(wnd,CB_SETCURSEL,-1,0);
end;

procedure FillActionList(wnd:HWND);
var
  ptr,ptr1:pChain;
  i,cnt:integer;
begin
  cnt:=CallService(MS_ACT_GETLIST,0,LPARAM(@ptr));
  SendMessage(wnd,CB_RESETCONTENT,0,0);
  if cnt>0 then
  begin
    ptr1:=ptr;
    inc(pbyte(ptr),4);
    for i:=0 to cnt-1 do
    begin
      CB_AddStrDataW(wnd,ptr^.descr,ptr^.id);
      inc(ptr);
    end;

    CallService(MS_ACT_FREELIST,0,LPARAM(ptr1));
    SendMessage(wnd,CB_SETCURSEL,0,0);
  end;
end;

function ActListChange(wParam:WPARAM;lParam:LPARAM):integer; cdecl;
begin
  result:=0;
  if settings<>0 then
    FillActionList(GetDlgItem(settings,IDC_ACTIONLIST));
end;

procedure ShowHookData(Dialog:HWND; item:integer=-1);
var
  li:LV_ITEM;
  arr:array [0..127] of WideChar;
  wnd:HWND;
begin
  wnd:=GetDlgItem(Dialog,IDC_HOOKLIST);
  if item<0 then
    li.iItem:=SendMessage(wnd,LVM_GETNEXTITEM,-1,LVNI_FOCUSED)
  else
    li.iItem:=item;

  li.mask      :=LVIF_TEXT+LVIF_PARAM;
  li.iSubItem  :=1;
  li.pszText   :=@arr;
  li.cchTextMax:=SizeOf(arr) div SizeOf(WideChar);
  arr[0]:=#0;
  SendMessageW(wnd,LVM_GETITEMW,0,LPARAM(@li));
  if arr[0]<>#0 then
    SetDlgItemTextW(Dialog,IDC_EVENTLIST,arr);
  CB_SelectData(GetDlgItem(Dialog,IDC_ACTIONLIST),li.lParam);
end;

procedure SaveHookData(Dialog:HWND; item:integer=-1);
var
  wnd:HWND;
  li:LV_ITEM;
begin
  wnd:=GetDlgItem(Dialog,IDC_HOOKLIST);
  if item<0 then
    li.iItem:=SendMessage(wnd,LVM_GETNEXTITEM,-1,LVNI_FOCUSED)
  else
    li.iItem:=item;
  li.mask      :=LVIF_PARAM;
  li.lParam    :=CB_GetData(GetDlgItem(Dialog,IDC_ACTIONLIST));
  li.iSubItem  :=0;
  SendMessageW(wnd,LVM_SETITEMW,0,LPARAM(@li));
  li.mask      :=LVIF_TEXT;
  li.iSubItem  :=1;
  li.pszText   :=GetDlgText(Dialog,IDC_EVENTLIST);
  SendMessageW(wnd,LVM_SETITEMW,0,LPARAM(@li));
  mFreeMem(li.pszText);
end;

function NewHook(Dialog:HWND;item:integer=-1):integer;
var
  wnd:HWND;
  li:LV_ITEMW;
begin
  wnd:=GetDlgItem(Dialog,IDC_HOOKLIST);
  li.mask    :=LVIF_TEXT;
  if item<0 then
    li.iItem :=SendMessage(wnd,LVM_GETNEXTITEM,-1,LVNI_FOCUSED)+1
  else
    li.iItem :=item;
  li.iSubItem:=0;
  li.pszText :=TranslateW('hook sample');
  result:=SendMessageW(wnd,LVM_INSERTITEMW,0,LPARAM(@li));
end;

function DeleteHook(Dialog:HWND):integer;
var
  wnd:HWND;
  i:integer;
begin
  result:=0;
  wnd:=GetDlgItem(Dialog,IDC_HOOKLIST);
  for i:=ListView_GetItemCount(wnd)-1 downto 0 do
  begin
    if ListView_GetItemState(wnd,i,LVIS_SELECTED)<>0 then
      SendMessage(wnd,LVM_DELETEITEM,i,0);
  end;
  Listview_SetItemState(wnd,0,LVIS_FOCUSED or LVIS_SELECTED,
                              LVIS_FOCUSED or LVIS_SELECTED);
end;

function NewHKTableProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):lresult; stdcall;
var
  i:integer;
begin
  result:=0;
  case hMessage of
    WM_KEYDOWN: begin
      if (lParam and (1 shl 30))=0 then
      begin
        case wParam of
          VK_F2: begin
            i:=SendMessage(Dialog,LVM_GETNEXTITEM,-1,LVNI_FOCUSED);
            if i>=0 then
              PostMessageW(Dialog,LVM_EDITLABELW,i,0);
            exit;
          end;
          VK_INSERT: begin
            PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDC_HOOK_NEW,0);
            exit;
          end;
          VK_DELETE: begin
            PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDC_HOOK_DELETE,0);
            exit;
          end;
        end;
      end;
    end;
  end;
  result:=CallWindowProc(OldTableProc,Dialog,hMessage,wParam,lParam);
end;

procedure SetIcons(Dialog:HWND);
var
  ti:TTOOLINFOW;
  hwndTooltip:HWND;
begin
  hwndTooltip:=CreateWindowW(TOOLTIPS_CLASS,nil,TTS_ALWAYSTIP,
      integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
      integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
      Dialog,0,hInstance,nil);

  FillChar(ti,SizeOf(ti),0);
  ti.cbSize  :=sizeof(TOOLINFO);
  ti.uFlags  :=TTF_IDISHWND or TTF_SUBCLASS;
  ti.hwnd    :=dialog;
  ti.hinst   :=hInstance;

  ti.uId     :=GetDlgItem(Dialog,IDC_EVENT_HELP);
  ti.lpszText:=TranslateW('Help');
  SendMessage(ti.uId,BM_SETIMAGE,IMAGE_ICON,
      CallService(MS_SKIN_LOADICON,SKINICON_OTHER_HELP,0));
  SendMessageW(hwndTooltip,TTM_ADDTOOLW,0,LPARAM(@ti));
  
  ti.uId     :=GetDlgItem(Dialog,IDC_HOOK_NEW);
  ti.lpszText:=TranslateW('New');
  SetButtonIcon(ti.uId,ACI_NEW);
  SendMessageW(hwndTooltip,TTM_ADDTOOLW,0,LPARAM(@ti));
  ti.uId     :=GetDlgItem(Dialog,IDC_HOOK_DELETE);
  ti.lpszText:=TranslateW('Delete');
  SetButtonIcon(ti.uId,ACI_DELETE);
  SendMessageW(hwndTooltip,TTM_ADDTOOLW,0,LPARAM(@ti));
end;

function DlgProcOpt(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):lresult; stdcall;
var
  wnd:HWND;
  lv:LV_COLUMNW;
  i:integer;
  tmp:pAnsiChar;
  buf:array [0..255] of AnsiChar;
begin
  result:=0;
  case hMessage of
    WM_CLOSE: begin
      PluginLink^.UnhookEvent(onactchanged);
      settings:=0;
    end;

    WM_INITDIALOG: begin
      wnd:=GetDlgItem(Dialog,IDC_HOOKLIST);
      SendMessage(wnd,LVM_SETUNICODEFORMAT,1,0);
      FillChar(lv,SizeOf(lv),0);
      lv.mask   :=LVCF_TEXT or LVCF_WIDTH;
      lv.pszText:=TranslateW('Description');
      lv.cx     :=110;
      SendMessageW(wnd,LVM_INSERTCOLUMNW ,0,TLPARAM(@lv));
      lv.pszText:=TranslateW('Name');
      lv.cx     :=110;
      SendMessageW(wnd,LVM_INSERTCOLUMNW ,1,TLPARAM(@lv));
      SendMessageW(wnd,LVM_SETCOLUMNWIDTH,1,LVSCW_AUTOSIZE_USEHEADER);
//      SendMessage (wnd,LVM_SETEXTENDEDLISTVIEWSTYLE,LVS_EX_CHECKBOXES,LVS_EX_CHECKBOXES);
      SendMessage (wnd,LVM_SETEXTENDEDLISTVIEWSTYLE,0,
          LVS_EX_FULLROWSELECT or LVS_EX_CHECKBOXES or LVS_EX_GRIDLINES);
      SendMessage(wnd,LVM_SETUNICODEFORMAT,1,0);
      OldTableProc:=pointer(SetWindowLongPtrW(wnd,GWL_WNDPROC,LONG_PTR(@NewHKTableProc)));
      TranslateDialogDefault(Dialog);

      SetIcons(Dialog);

      FillEventList (GetDlgItem(Dialog,IDC_EVENTLIST));
      FillActionList(GetDlgItem(Dialog,IDC_ACTIONLIST));
      FillHookList(wnd);
      ShowHookData(Dialog);

      onactchanged:=PluginLink^.HookEvent(ME_ACT_CHANGED,@ActListChange);
      settings:=Dialog;
    end;

    WM_HELP: ;

    WM_RESETHOOKS:begin
      FillHookList(GetDlgItem(Dialog,IDC_HOOKLIST));
    end;

    WM_COMMAND: begin
      case wParam shr 16 of
        EN_CHANGE,
        CBN_EDITCHANGE,
        CBN_SELCHANGE: begin
          SendMessage(GetParent(Dialog),PSM_CHANGED,0,0);
        end;
      end;

      case wParam shr 16 of
        CBN_EDITCHANGE,
        CBN_SELCHANGE: begin
          case loword(wParam) of
            IDC_EVENTLIST: begin
              tmp:=GetDlgText(Dialog,IDC_EVENTLIST,true);
              buf[0]:=#0;
              if (tmp<>nil) and (tmp^<>#0) then
                GetPrivateProfileStringA(tmp,'descr','',buf,SizeOf(buf),'plugins\events.ini');
              SetDlgItemTextA(Dialog,IDC_DESCR,@buf);
              mFreeMem(tmp);
            end;
          end;
          SendMessage(GetParent(Dialog),PSM_CHANGED,0,0);
        end;

        BN_CLICKED: begin
          case loword(wParam) of
            IDC_EVENT_HELP : ;
            IDC_HOOK_NEW   : NewHook(Dialog);
            IDC_HOOK_DELETE: DeleteHook(Dialog);
          end;
        end;
      end;
    end;

    WM_NOTIFY: begin
      case integer(PNMHdr(lParam)^.code) of
        PSN_APPLY: begin
          SaveHookData(Dialog);
          CheckHookList(GetDlgItem(Dialog,IDC_HOOKLIST));
          SetAllHooks;
          SaveHooks;
        end;

        NM_DBLCLK: begin
          if PNMListView(lParam)^.iItem>=0 then
            PostMessageW(PNMHdr(lParam)^.hWndFrom,LVM_EDITLABELW,
                        PNMListView(lParam)^.iItem,0);
        end;

        LVN_ENDLABELEDITW: begin
          with PLVDISPINFOW(lParam)^ do
          begin
            if item.pszText<>nil then
            begin
              item.mask:=LVIF_TEXT;
              SendMessageW(hdr.hWndFrom,LVM_SETITEMW,0,TLPARAM(@item));
            end;
          end;
          result:=1;
        end;

        LVN_ITEMCHANGED: begin
          if PNMLISTVIEW(lParam)^.uChanged=LVIF_STATE then
          begin
            i:=(PNMLISTVIEW(lParam)^.uOldState and LVNI_FOCUSED)-
               (PNMLISTVIEW(lParam)^.uNewState and LVNI_FOCUSED);

            if i>0 then // old focus
              SaveHookData(Dialog,PNMLISTVIEW(lParam)^.iItem)
            else if i<0 then // new focus
            begin
              ShowHookData(Dialog,PNMLISTVIEW(lParam)^.iItem);
            end
            else if (settings<>0) and
               ((PNMLISTVIEW(lParam)^.uOldState or PNMLISTVIEW(lParam)^.uNewState)=$3000) then
              SendMessage(GetParent(Dialog),PSM_CHANGED,0,0);
          end;
        end;
      end;
    end;
  end;
end;