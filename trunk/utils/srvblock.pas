unit srvblock;

interface

uses
  windows;

const
  ACF_SCRIPT_SERVICE = $01000000; // high byte of dword

type
  pServiceValue = ^tServiceValue;
  tServiceValue = record
    service:pAnsiChar;
    wparam,
    lparam: pointer;
    w_flag,
    l_flag,
    flags:dword; // result etc
  end;

function CreateServiceBlock(parent:HWND;x,y,width,height:integer;flags:dword=0):HWND;

function SetSrvBlockValue(Dialog:HWND;const value:tServiceValue):boolean;
function GetSrvBlockValue(Dialog:HWND;var   value:tServiceValue):boolean;

procedure SetSrvBlockService(Dialog:HWND; service:pAnsiChar);
function  GetSrvBlockService(Dialog:HWND):pAnsiChar;

implementation

uses
  messages,
  common, m_api,
  wrapper,Editwrapper,
  mApiCardM, sparam;

const
  IDC_S_SERVICE  = 2040;
  IDC_C_SERVICE  = 2041;
  IDC_CLOSE_WPAR = 2042;
  IDC_CLOSE_LPAR = 2043;
  IDC_CLOSE_RES  = 2044;

function GetWPar(Dialog:HWND):HWND;
begin
  result:=GetWindowLongPtrW(GetDlgItem(Dialog,IDC_CLOSE_WPAR),GWLP_USERDATA);
end;

function GetLPar(Dialog:HWND):HWND;
begin
  result:=GetWindowLongPtrW(GetDlgItem(Dialog,IDC_CLOSE_LPAR),GWLP_USERDATA);
end;

function GetRes(Dialog:HWND):HWND;
begin
  result:=GetWindowLongPtrW(GetDlgItem(Dialog,IDC_CLOSE_RES),GWLP_USERDATA);
end;

procedure ShowBlock(Dialog:HWND;id:integer);
var
  wpar ,lpar ,res:HWND;
  wparb,lparb,resb:HWND;
  wnd,wndb:HWND;
  rc,rc1:TRECT;
  pt:TPOINT;
begin
  // buttons
  wpar:=GetDlgItem(Dialog,IDC_CLOSE_WPAR);
  lpar:=GetDlgItem(Dialog,IDC_CLOSE_LPAR);
  res :=GetDlgItem(Dialog,IDC_CLOSE_RES);

  // blocks
  wparb:=GetWindowLongPtrW(wpar,GWLP_USERDATA);
  lparb:=GetWindowLongPtrW(lpar,GWLP_USERDATA);
  resb :=GetWindowLongPtrW(res ,GWLP_USERDATA);

  if id=0 then
  begin
    ShowWindow(wparb,SW_HIDE);
    ShowWindow(lparb,SW_HIDE);
    ShowWindow(resb ,SW_HIDE);
    exit;
  end;

  // starting point of coords
  GetWindowRect(wpar,rc);
  pt.x:=rc.left;
  pt.y:=rc.bottom;
  ScreenToClient(Dialog,pt);
  // show/hide blocks
  // enable/disable buttons
  // move buttons to new place
  case id of
    IDC_CLOSE_WPAR: begin
      CheckDlgButton(Dialog,IDC_CLOSE_WPAR,BST_CHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_LPAR,BST_UNCHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_RES ,BST_UNCHECKED);
      EnableWindow(lpar,true);
      EnableWindow(res ,true);
      ShowWindow(lparb,SW_HIDE);
      ShowWindow(resb ,SW_HIDE);
      wnd :=wpar;
      wndb:=wparb;

      GetClientRect(wparb,rc1);
      SetWindowPos(lpar,HWND_TOP,pt.x,pt.y+rc1.bottom+5,0,0,SWP_NOZORDER or SWP_NOSIZE);
      GetClientRect(lpar,rc);
      SetWindowPos(res,HWND_TOP,pt.x,pt.y+rc1.bottom+rc.bottom+10,0,0,SWP_NOZORDER or SWP_NOSIZE);
    end;

    IDC_CLOSE_LPAR: begin
      CheckDlgButton(Dialog,IDC_CLOSE_WPAR,BST_UNCHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_LPAR,BST_CHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_RES ,BST_UNCHECKED);
      EnableWindow(wpar,true);
      EnableWindow(res ,true);
      ShowWindow(wparb,SW_HIDE);
      ShowWindow(resb ,SW_HIDE);
      wnd :=lpar;
      wndb:=lparb;

      SetWindowPos(lpar,HWND_TOP,pt.x,pt.y+5,0,0,SWP_NOZORDER or SWP_NOSIZE);
      GetClientRect(lpar ,rc);
      GetClientRect(lparb,rc1);
      SetWindowPos(res,HWND_TOP,pt.x,pt.y+rc1.bottom+rc.bottom+10,0,0,SWP_NOZORDER or SWP_NOSIZE);
    end;

    IDC_CLOSE_RES: begin
      CheckDlgButton(Dialog,IDC_CLOSE_WPAR,BST_UNCHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_LPAR,BST_UNCHECKED);
      CheckDlgButton(Dialog,IDC_CLOSE_RES ,BST_CHECKED);
      EnableWindow(wpar,true);
      EnableWindow(lpar,true);
      ShowWindow(wparb,SW_HIDE);
      ShowWindow(lparb,SW_HIDE);
      wnd :=res;
      wndb:=resb;

      SetWindowPos(lpar,HWND_TOP,pt.x,pt.y+5,0,0,SWP_NOZORDER or SWP_NOSIZE);
      GetClientRect(lpar,rc);
      SetWindowPos(res,HWND_TOP,pt.x,pt.y+rc.bottom+10,0,0,SWP_NOZORDER or SWP_NOSIZE);
    end;
  end;
  EnableWindow(wnd ,false);
  ShowWindow  (wndb,SW_SHOW);
end;

procedure ReloadService(Dialog:HWND;srv:pAnsiChar;setvalue:boolean);
var
  pc:pAnsiChar;
  ApiCard:tmApiCard;
  flag:dword;
begin
  ApiCard:=tmApiCard(GetWindowLongPtrW(GetDlgItem(Dialog,IDC_S_SERVICE),GWLP_USERDATA));
  ApiCard.Service:=srv;

  pc:=ApiCard.FillParams(0,true);
  if pc<>nil then
  begin
    FillParam(GetWPar(Dialog),pc);
(*
    if GetDlgItemTextA(Dialog,IDC_EDIT_WPAR,buf1,SizeOf(buf1))>0 then
      case FixParam(Dialog,@buf1,IDC_FLAG_WPAR) of
        ptStruct: begin
          if setvalue then
          begin
            struct:=pAnsiChar(SetWindowLongPtrW(GetDlgItem(Dialog,IDC_WSTRUCT),GWLP_USERDATA,
            long_ptr(StrDup(struct,StrScan(pc,'|')+1))));
            mFreeMem(struct);
          end;

{          struct:=pAnsiChar(GetWindowLongPtrW(GetDlgItem(Dialog,IDC_WSTRUCT),GWLP_USERDATA));
          mFreeMem(struct);
          StrDup(struct,StrScan(pc,'|')+1);
          SetWindowLongPtrW(GetDlgItem(Dialog,IDC_WSTRUCT),GWLP_USERDATA,long_ptr(struct));
//            AnsiToWide(StrScan(pc,'|')+1,wstruct,MirandaCP);
}
        end;
      end;
*)
    mFreeMem(pc);
  end;

  pc:=ApiCard.FillParams(0,false);
  if pc<>nil then
  begin
    FillParam(GetLPar(Dialog),pc);
    mFreeMem(pc);
  end;

  pc:=ApiCard.ResultType;
  flag:=ACF_RNUMBER;
  if pc<>nil then
  begin
    if      lstrcmpia(pc,'struct')=0 then flag:=ACF_RSTRUCT
    else if lstrcmpia(pc,'str')=0 then
    begin
      flag:=ACF_RSTRING;
    end
    else if lstrcmpia(pc,'wide')=0 then
    begin
      flag:=ACF_RUNICODE;
    end;
    mFreeMem(pc);
  end;

  SetResultValue(GetRes(Dialog),flag);
end;

procedure FillTemplate(Dialog:HWND);
var
  wnd:HWND;
  buf:array [0..127] of AnsiChar;
begin
  wnd:=GetDlgItem(Dialog,IDC_C_SERVICE);
  SendMessageA(wnd,CB_GETLBTEXT,SendMessage(wnd,CB_GETCURSEL,0,0),tlparam(@buf));
  ReloadService(Dialog,@buf,true);
end;

function DlgServiceProc(Dialog:HWnd;hMessage:uint;wParam:WPARAM;lParam:LPARAM):lresult; stdcall;
var
  proc:pointer;
  pc:pAnsiChar;
  ApiCard:tmApiCard;
begin
  result:=0;

  case hMessage of
    WM_DESTROY: begin
      ApiCard:=tmApiCard(GetWindowLongPtrW(GetDlgItem(Dialog,IDC_S_SERVICE),GWLP_USERDATA));
      if ApiCard<>nil then
        ApiCard.Free;
    end;

    WM_COMMAND: begin
      case wParam shr 16 of
        CBN_EDITCHANGE,
        EN_CHANGE: begin
          SendMessage(GetParent(Dialog),WM_COMMAND,CBN_EDITCHANGE shl 16,Dialog);
        end;

        BN_CLICKED: begin
          case loword(wParam) of
            IDC_CLOSE_WPAR,
            IDC_CLOSE_LPAR,
            IDC_CLOSE_RES: ShowBlock(Dialog,loword(wParam));
          end;
        end;

        CBN_SELCHANGE:  begin
          case loword(wParam) of
            IDC_C_SERVICE: FillTemplate(Dialog);
          end;
        end;
        //!!
        WM_HELP: begin
          ApiCard:=tmApiCard(GetWindowLongPtrW(GetDlgItem(Dialog,IDC_S_SERVICE),GWLP_USERDATA));
          pc:=ApiCard.NameFromList(GetDlgItem(Dialog,IDC_C_SERVICE));
          ApiCard.Service:=pc;
          mFreeMem(pc);
          ApiCard.Show;

          result:=1;
        end;
      end;
    end;
  else
    proc:=pointer(GetWindowLongPtrW(Dialog,GWLP_USERDATA));
    result:=CallWindowProc(proc,Dialog,hMessage,wParam,lParam)
  end;
end;

function CreateServiceBlock(parent:HWND;x,y,width,height:integer;flags:dword=0):HWND;
var
  hf:HFONT;
  ctrl,wnd,srv,srvs:HWND;
  proc:pointer;
  ApiCard:tmApiCard;
  rc:TRECT;
  dx,dy:integer;
  ux,uy:integer;
begin
  hf:=SendMessageW(parent,WM_GETFONT,0,0);
  GetUnitSize(parent,ux,uy);

  // let think what x,y and width is dialog-related
  SetRect(rc,x,y,x+width,y+height);
  dx:=rc.right-rc.left;

  result:=CreateWindowExW(WS_EX_CONTROLPARENT,'STATIC',nil,WS_CHILD+WS_VISIBLE,
          x,y,dx,rc.bottom-rc.top, parent,0,hInstance,nil);
  proc:=pointer(SetWindowLongPtrW(result,GWLP_WNDPROC,long_ptr(@DlgServiceProc)));
  SetWindowLongPtrW(result,GWLP_USERDATA,long_ptr(proc));
  SendMessageW(result,WM_SETFONT,hf,0);

  dy:=0;
  // Service label
  rc.bottom:=12*uy div 8;
  srvs:=CreateWindowW('STATIC','Service:',WS_CHILD+WS_VISIBLE+SS_CENTERIMAGE+SS_LEFT,
        0,dy,dx,rc.bottom, result,IDC_S_SERVICE,hInstance,nil);
  SendMessageW(srvs,WM_SETFONT,hf,0);
  inc(dy,rc.bottom+2);

  // Service name combobox
  rc.bottom:=14*uy div 8;
  srv:=CreateWindowW('COMBOBOX',nil,WS_CHILD+WS_VISIBLE+WS_VSCROLL+CBS_DROPDOWN+CBS_AUTOHSCROLL,
        0,dy,dx,76, result,IDC_C_SERVICE,hInstance,nil);
  SendMessageW(srv,WM_SETFONT,hf,0);
  inc(dy,rc.bottom+2);
  MakeEditField(result,IDC_C_SERVICE);

  // wParam button+block
  rc.bottom:=11*uy div 8;
  ctrl:=CreateWindowW('BUTTON','wParam',WS_CHILD+WS_VISIBLE+BS_AUTOCHECKBOX+BS_PUSHLIKE,
        0,dy,dx,rc.bottom, result,IDC_CLOSE_WPAR,hInstance,nil);
  SendMessageW(ctrl,WM_SETFONT,hf,0);
  inc(dy,rc.bottom+4);

  wnd:=CreateParamBlock(result,0,dy,dx,flags);
  SetWindowLongPtrW(ctrl,GWLP_USERDATA,wnd);
  SetParamLabel(wnd,'wParam');

  // lParam button+block
  ctrl:=CreateWindowW('BUTTON','lParam',WS_CHILD+WS_VISIBLE+BS_AUTOCHECKBOX+BS_PUSHLIKE,
        0,dy,dx,rc.bottom, result,IDC_CLOSE_LPAR,hInstance,nil);
  SendMessageW(ctrl,WM_SETFONT,hf,0);
  inc(dy,rc.bottom+4);

  wnd:=CreateParamBlock(result,0,dy,dx,flags);
  SetWindowLongPtrW(ctrl,GWLP_USERDATA,wnd);
  SetParamLabel(wnd,'lParam');

  // result button+block
  ctrl:=CreateWindowW('BUTTON','Result',WS_CHILD+WS_VISIBLE+BS_AUTOCHECKBOX+BS_PUSHLIKE,
        0,dy,dx,rc.bottom, result,IDC_CLOSE_RES,hInstance,nil);
  SendMessageW(ctrl,WM_SETFONT,hf,0);
  inc(dy,rc.bottom+4);

  SetWindowLongPtrW(ctrl,GWLP_USERDATA,CreateResultBlock(result,0,dy,dx,flags));

  // additional
  ApiCard:=CreateServiceCard(result);
  ApiCard.FillList(srv);
  SetWindowLongPtrW(srvs,GWLP_USERDATA,long_ptr(ApiCard));

  ShowBlock(result,IDC_CLOSE_WPAR);
end;

function SetSrvBlockValue(Dialog:HWND;const value:tServiceValue):boolean;
begin
  result:=true;

  if CB_SelectData(Dialog,IDC_C_SERVICE,Hash(value.service,StrLen(value.service)))<>CB_ERR then
;{
    ReloadService(Dialog,value.service,false)
  else
}
    SetDlgItemTextA(Dialog,IDC_C_SERVICE,value.service);

  SetEditFlags(GetDlgItem(Dialog,IDC_C_SERVICE),EF_SCRIPT,
        ord((value.flags and ACF_SCRIPT_SERVICE)<>0));

  SetParamValue (GetWPar(Dialog),value.w_flag,value.wparam);
  SetParamValue (GetLPar(Dialog),value.l_flag,value.lparam);
  SetResultValue(GetRes (Dialog),value.flags and ACF_RTYPE);
end;

function GetSrvBlockValue(Dialog:HWND;var value:tServiceValue):boolean;
var
  ApiCard:tmApiCard;
begin
  result:=true;

  ApiCard:=tmApiCard(GetWindowLongPtrW(GetDlgItem(Dialog,IDC_S_SERVICE),GWLP_USERDATA));
  value.service:=ApiCard.NameFromList(GetDlgItem(Dialog,IDC_C_SERVICE));

  GetParamValue(GetWPar(Dialog),value.w_flag,value.wparam);
  GetParamValue(GetLPar(Dialog),value.l_flag,value.lparam);
  value.flags:=GetResultValue(GetRes(Dialog));

  if (GetEditFlags(Dialog,IDC_C_SERVICE) and EF_SCRIPT)<>0 then
    value.flags:=value.flags or ACF_SCRIPT_SERVICE;
end;

procedure SetSrvBlockService(Dialog:HWND; service:pAnsiChar);
begin
  ReloadService(Dialog,service,true);
end;

function GetSrvBlockService(Dialog:HWND):pAnsiChar;
begin
  result:=GetDlgText(Dialog,IDC_C_SERVICE);
end;

end.