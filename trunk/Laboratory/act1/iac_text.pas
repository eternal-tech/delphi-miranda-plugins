unit iac_text;

interface

implementation

uses
  windows, messages,
  iac_global, m_api, editwrapper,
  dbsettings, common, io,
  mirutils, syswin, wrapper;

{$include i_cnst_text.inc}
{$resource iac_text.res}

const
  BufferSize = 32768; // chars

const
  opt_text = 'text';

const
  ACF_TEXTSCRIPT = $00000001;

type
  tTextAction = class(tBaseAction)
    text: pWideChar;

    constructor Create(uid:dword);
    destructor Destroy; override;
//    function  Clone:tBaseAction; override;
    function  DoAction(var WorkData:tWorkData):LRESULT; override;
    procedure Save(node:pointer;fmt:integer); override;
    procedure Load(node:pointer;fmt:integer); override;
  end;

//----- Support functions -----

//----- Object realization -----

constructor tTextAction.Create(uid:dword);
begin
  inherited Create(uid);

  text:=nil;
end;

destructor tTextAction.Destroy;
begin
  mFreeMem(text);

  inherited Destroy;
end;
{
function tTextAction.Clone:tBaseAction;
begin
  result:=.Create(0);
  Duplicate(result);

end;
}
type
  trec = record
    text:PAnsiChar;
    one, two:integer;
  end;

function GetFileString(fname:PAnsiChar;linenum:integer):pWideChar;
var
  pc,FileBuf,CurLine:PAnsiChar;
  f:THANDLE;
  NumLines, j:integer;
begin
  f:=Reset(fname);
  if f<>INVALID_HANDLE_VALUE then
  begin
    j:=FileSize(f);
    mGetMem(FileBuf,j+1);
    BlockRead(f,FileBuf^,j);
    while (FileBuf+j)^<' ' do dec(j);
    (FileBuf+j+1)^:=#0;
    CloseHandle(f);
    pc:=FileBuf;
    CurLine:=pc;
    NumLines:=1;
    while pc^<>#0 do // count number of lines
    begin
      if pc^=#13 then
      begin
        if linenum=NumLines then
          break;
        inc(pc);
        if pc^=#10 then
          inc(pc);
        inc(NumLines);
        CurLine:=pc;
      end
      else
        inc(pc);
    end;
    if (linenum>NumLines) or (linenum=0) then //ls - lastline
    else if linenum<0 then
    begin
      randomize;
      linenum:=random(NumLines)+1;
      pc:=FileBuf;
      NumLines:=1;
      CurLine:=pc;
      repeat
        if (pc^=#13) or (pc^=#0) then
        begin
          if linenum=NumLines then
            break;
          if pc^<>#0 then
          begin
            inc(pc);
            if pc^=#10 then
              inc(pc);
          end;
          inc(NumLines);
          CurLine:=pc;
        end
        else
          inc(pc);
      until false;
    end;
    pc^:=#0;
    StrReplace(CurLine,'\n',#13#10);
    StrReplace(CurLine,'\t',#09);
    AnsiToWide(CurLine,result,CP_ACP);
    mFreeMem(FileBuf);
  end
  else
    result:=nil;
end;

function Split(buf:PWideChar;macro:PWideChar;var r:trec):integer;
type
  tconv = packed record
    case boolean of
      false: (res:int);
      true: (lo,hi:word);
  end;
var
  i:integer;
  p,pp,lp:pWideChar;
  ls:array [0..511] of WideChar;
begin
  result:=0;
  i:=StrIndexW(buf,macro);
  if i>0 then
  begin
    dec(i);
    p:=buf+i+StrLenW(macro);
    pp:=p;
    while (p^<>#0) and (p^<>')') do
      inc(p);
    ls[0]:=#0;
    if p^<>#0 then // correct syntax
    begin
      lp:=ls;
      while (pp<>p) and (pp^<>',') do // filename
      begin
        lp^:=pp^;
        inc(lp);
        inc(pp);
      end;
      lp^:=#0;
      WideToAnsi(ls,r.text,MirandaCP);
      r.one:=-1;
      r.two:=-1;
      if pp^=',' then
      begin
        inc(pp);
        r.one:=StrToInt(pp);
        while (pp<>p) and (pp^<>',') do inc(pp);
        if pp^=',' then
        begin
          inc(pp);
          r.two:=StrToInt(pp);
        end;
      end;
      tconv(result).lo:=p-buf-i+1; // length
      tconv(result).hi:=i;   // position
    end;
  end;
end;

procedure PasteFileString(dst:pWideChar);
var
  i:integer;
  lp:pWideChar;
  buf:array [0..511] of AnsiChar;
  r:trec;
begin
  repeat
    i:=Split(dst,'^f(',r);
    if i>0 then
    begin
      StrDeleteW(dst,i shr 16,loword(i));
      ConvertFileName(r.text,buf);
//      CallService(MS_UTILS_PATHTOABSOLUTE,WPARAM(r.text),LPARAM(@buf));
      lp:=GetFileString(@buf,r.one);
      if lp<>nil then
      begin
        StrInsertW(lp,dst,i shr 16);
        mFreeMem(lp);
      end;
    end
    else
      break;
  until false;
end;

procedure PasteClipboard(dst:pWideChar);
var
  p:pWideChar;
  fh:tHandle;
begin
  if StrPosW(dst,'^v')<>nil then
  begin
    if OpenClipboard(0) then
    begin
      fh:=GetClipboardData(cf_UnicodeText);
      p:=GlobalLock(fh);
      StrReplaceW(dst,'^v',p);
      GlobalUnlock(fh);
      CloseClipboard;
    end
  end
end;

procedure PasteSelectedText(dst:pWideChar);
var
  sel:integer;
  buf:pWideChar;
  wnd:HWND;
begin
  if StrPosW(dst,'^s')<>nil then
  begin
    wnd:=WaitFocusedWndChild(GetForegroundWindow){GetFocus};
    if wnd<>0 then
    begin
      sel:=SendMessageW(wnd,EM_GETSEL,0,0);
      if loword(sel)=(sel shr 16) then
        StrReplaceW(dst,'^s',nil)
      else
      begin
        buf:=GetDlgText(wnd,false);
        buf[sel shr 16]:=#0;
        StrReplaceW(dst,'^s',buf+loword(sel));
        mFreeMem(buf);
      end;
    end
    else
      StrReplaceW(dst,'^s',nil);
  end;
end;

function tTextAction.DoAction(var WorkData:tWorkData):LRESULT;
var
  buf:array [0..31] of WideChar;
  w:pWideChar;
begin
  result:=0;

  mGetMem (w ,BufferSize*SizeOf(WideChar));
  FillChar(w^,BufferSize*SizeOf(WideChar),0);
  StrCopyW(w,text);

  PasteClipboard(w);    // ^v
  PasteFileString(w);   // ^f

  PasteSelectedText(w); // ^s
  // ^a - get ALL text?

  if WorkData.ResultType=rtInt then
  begin
    StrReplaceW(w,'^l',IntToStr(buf,WorkData.LastResult)); // ^l
    StrReplaceW(w,'^h',IntToHex(buf,WorkData.LastResult)); // ^h
  end
  else
  begin
    StrReplaceW(w,'^l',pWideChar(WorkData.LastResult));
    StrReplaceW(w,'^h',IntToHex(buf,StrToInt(pWideChar(WorkData.LastResult))));
  end;

  StrReplaceW(w,'^t',#9);   // ^t
  StrReplaceW(w,'^e',nil);  // ^e

  ClearResult(WorkData);
  WorkData.LastResult:=uint_ptr(w);
  WorkData.ResultType:=rtWide;
end;

procedure tTextAction.Load(node:pointer;fmt:integer);
var
  section: array [0..127] of AnsiChar;
  pc:pAnsiChar;
begin
  inherited Load(node,fmt);
  case fmt of
    0: begin
      pc:=StrCopyE(section,pAnsiChar(node));

      StrCopy(pc,opt_text); text:=DBReadUnicode(0,DBBranch,section,nil);
    end;
{
    1: begin
    end;
}
  end;
end;

procedure tTextAction.Save(node:pointer;fmt:integer);
var
  section: array [0..127] of AnsiChar;
  pc:pAnsiChar;
begin
  inherited Save(node,fmt);
  case fmt of
    0: begin
      pc:=StrCopyE(section,pAnsiChar(node));

      StrCopy(pc,opt_text); DBWriteUnicode(0,DBBranch,section,text);
    end;
{
    1: begin
    end;
}
  end;
end;

//----- Dialog realization -----

procedure ClearFields(Dialog:HWND);
begin
  SetDlgItemTextW(Dialog,IDC_TXT_TEXT,nil);
  SetEditFlags(Dialog,IDC_TXT_TEXT,EF_ALL,0);
end;

function DlgProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):lresult; stdcall;
begin
  result:=0;

  case hMessage of
    WM_INITDIALOG: begin
      TranslateDialogDefault(Dialog);

      MakeEditField(Dialog,IDC_TXT_TEXT);
    end;

    WM_ACT_SETVALUE: begin
      ClearFields(Dialog);

      with tTextAction(lParam) do
      begin
        SetDlgItemTextW(Dialog,IDC_TXT_TEXT,text);
        SetEditFlags(Dialog,IDC_TXT_TEXT,EF_SCRIPT,ord((flags and ACF_TEXTSCRIPT)<>0));
      end;
    end;

    WM_ACT_RESET: begin
      ClearFields(Dialog);
    end;

    WM_ACT_SAVE: begin
      with tTextAction(lParam) do
      begin
        flags:=0;

        {mFreeMem(text); }text:=GetDlgText(Dialog,IDC_TXT_TEXT);
        if (GetEditFlags(Dialog,IDC_TXT_TEXT) and EF_SCRIPT)<>0 then
           flags:=flags or ACF_TEXTSCRIPT;
      end;
    end;

{
    WM_COMMAND: begin
      case wParam shr 16 of
      end;
    end;
}
    WM_HELP: begin
      MessageBoxW(0,
        TranslateW('^s - selected (and replaced) part'#13#10+
        '^e - replaced by empty string'#13#10+
        '^v - paste text from Clipboard'#13#10+
        '^t - replaced by tabulation'#13#10+
        '^l - replaced by last result as unicode'#13#10+
        '^h - replaced by last result as hex'#13#10+
        '^f(name[,str])'#13#10+
        '     paste line from text file.'#13#10+
        '     brackets contents must be w/o spaces'),
        TranslateW('Text'),0);
      result:=1;
    end;

  end;
end;

//----- Export/interface functions -----

var
  vc:tActModule;

function CreateAction:tBaseAction;
begin
  result:=tTextAction.Create(vc.Hash);
end;

function CreateDialog(parent:HWND):HWND;
begin
  result:=CreateDialogW(hInstance,'IDD_ACTTEXT',parent,@DlgProc);
end;

procedure Init;
begin
  vc.Next    :=ModuleLink;

  vc.Name    :='Text';
  vc.Dialog  :=@CreateDialog;
  vc.Create  :=@CreateAction;
  vc.Icon    :='IDI_TEXT';

  ModuleLink :=@vc;
end;

begin
  Init;
end.
