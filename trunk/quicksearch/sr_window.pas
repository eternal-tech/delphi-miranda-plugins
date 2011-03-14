unit sr_window;

interface

uses windows;

function OpenSrWindow(apattern:PWideChar;flags:integer):boolean;
function BringToFront:integer;
function CloseSrWindow:boolean;
procedure WndChangeColumns(code:integer;column:integer=-1);

function OnContactAdded  (wParam:WPARAM;lParam:LPARAM):integer;cdecl;
function OnStatusChanged (wParam:WPARAM;lParam:LPARAM):integer;cdecl;
function OnContactDeleted(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
function OnAccountChanged(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
procedure RegisterColors;

const
  grid:HWND = 0;

implementation

uses kol,messages,commctrl,sr_global,m_api,common,dbsettings,mirutils,
    swrapper,wrapper,sr_optdialog;

const
  strCListDel:PAnsiChar='CList/DeleteContactCommand';
const
  LVS_EX_LABELTIP = $4000;
const
  hIconF   :HICON   = 0;
  hIconM   :HICON   = 0;
  mainwnd  :HWND    = 0;
  StatusBar:HWND    = 0;
  sortcoldn:THANDLE = 0;
  sortcolup:THANDLE = 0;
  gridbrush:HBRUSH  = 0;
const
  OldLVProc  :pointer = nil;
  OldProc    :pointer = nil;
  OldEditProc:pointer = nil;
const
  pattern:pWideChar = nil;
const
  QSF_INLIST  = $0001; // in constant list
  QSF_ACTIVE  = $0002; // contact in listview
  QSF_DELETED = $0004; // contact deleted
  QSF_PATTERN = $0008; // pattern check passed
  QSF_ACCDEL  = $0010; // account deleted
  QSF_ACCOFF  = $0020; // account disabled
  QSF_META    = $0040; // contact is metacontact
  QSF_SUBMETA = $0080; // contact is part of metacontact

type
  PQSRec = ^QSRec;
  QSRec = record // cell
    text:PWideChar;
    data:dword;
  end;
  PQSFRec = ^QSFRec;
  QSFRec = record // row
    contact:THANDLE;
    proto  :PAnsiChar;
    flags  :dword;
    status :dword;
    wparam :dword;
    lparam :dword;
  end;
var
  colorhook:THANDLE;
  MainBuf:array of array of QSRec;
  FlagBuf:array of QSFRec;
  LastMeta:integer;
  tstrMale,
  tstrFemale,
  tstrUnknown:PWideChar;
  colorder:array of integer;
  tablecolumns:integer;

const
  maxpattern = 8;
var
  patterns:array [0..maxpattern-1] of record
    str:PWideChar;
    res:bool;
  end;
const
  patstr:PWideChar=nil;
  numpattern:integer=0;

const
  TIMERID_HOVER = 10;
const
  TTShowed:bool=false;
  TTinstalled:bool = false;

const
  bkg_norm:pAnsiChar = 'Normal background';
  fgr_norm:pAnsiChar = 'Normal foreground';
  bkg_odd :pAnsiChar = 'Odd background';
  fgr_odd :pAnsiChar = 'Odd foreground';
  bkg_dis :pAnsiChar = 'Disabled account background';
  fgr_dis :pAnsiChar = 'Disabled account foreground';
  bkg_del :pAnsiChar = 'Deleted account background';
  fgr_del :pAnsiChar = 'Deleted account foreground';
  bkg_hid :pAnsiChar = 'Hidden contact background';
  fgr_hid :pAnsiChar = 'Hidden contact foreground';
  bkg_meta:pAnsiChar = 'Metacontact background';
  fgr_meta:pAnsiChar = 'Metacontact foreground';
  bkg_sub :pAnsiChar = 'SubMetacontact background';
  fgr_sub :pAnsiChar = 'SubMetacontact foreground';

var
  cbkg_norm,
  cfgr_norm,
  cbkg_odd,
  cfgr_odd,
  cbkg_dis,
  cfgr_dis,
  cbkg_del,
  cfgr_del,
  cbkg_hid,
  cfgr_hid,
  cbkg_meta,
  cfgr_meta,
  cbkg_sub,
  cfgr_sub:TCOLORREF;
  
function GetQSColumn(item:integer):integer;
var
  i:integer;
begin
  for i:=0 to qsopt.numcolumns-1 do
  begin
    if colorder[i]=item then
    begin
      result:=i;
      exit;
    end;
  end;
  result:=-1;
end;

procedure SwitchOrder(var src,dst:array of dword);
var
  i:integer;
begin
  for i:=0 to HIGH(src) do
  begin
    dst[src[i]]:=i;
  end;
end;

procedure ShiftColumns(item,shift:integer); // item - table item, order - new screen order
var
  i,col:integer;
  buf:QSRec;
  lsize,lshift:integer;
begin
  col:=-1;
  for i:=0 to qsopt.numcolumns-1 do
  begin
    if (qsopt.columns[i].flags and COL_ON)<>0 then
    begin
      if shift=0 then
        col:=i; // new position
      dec(shift);
    end;
    if colorder[i]=item then
    begin
      lshift:=i; // column in buffer
    end;
  end;
  item:=lshift;
  shift:=col-item;

  col:=colorder[item];
  lsize:=sizeof(QSRec)*abs(shift);
  lshift:=item+shift;
  if shift>0 then
  begin
    for i:=0 to HIGH(Mainbuf) do
    begin
      buf:=MainBuf[i,item];
      move(MainBuf[i,item+1],MainBuf[i,item],lsize);
      MainBuf[i,lshift]:=buf;
    end;

    move(colorder[item+1],colorder[item],SizeOf(integer)*shift);
  end
  else // shift<0
  begin
    for i:=0 to HIGH(Mainbuf) do
    begin
      buf:=MainBuf[i,item];
      move(MainBuf[i,lshift],MainBuf[i,lshift+1],lsize);
      MainBuf[i,lshift]:=buf;
    end;

    move(colorder[lshift],colorder[lshift+1],sizeof(integer)*(-shift));
  end;
  colorder[lshift]:=col;
  OptChangeColumns(wcUp,item,shift);
end;

function GetColor(name:pAnsiChar):TCOLORREF;
var
  cid:TColourID;
begin
  cid.cbSize:=SizeOf(cid);
  StrCopy(cid.group,'QuickSearch');
  StrCopy(cid.name ,name);
  result:=CallService(MS_COLOUR_GETA,dword(@cid),0);
end;

procedure RegisterColors;
var
  cid:TColourID;
begin
  cid.cbSize:=SizeOf(cid);
  cid.flags :=0;
  StrCopy(cid.group,'QuickSearch');
  StrCopy(cid.dbSettingsGroup,qs_module);

  StrCopy(cid.name   ,bkg_norm);
  StrCopy(cid.setting,'back_norm');
  cid.defcolour:=$00FFFFFF;
  cid.order    :=0;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_norm);
  StrCopy(cid.setting,'fore_norm');
  cid.defcolour:=$00000000;
  cid.order    :=1;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_odd);
  StrCopy(cid.setting,'back_odd');
  cid.defcolour:=$00EBE6DE;
  cid.order    :=2;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_odd);
  StrCopy(cid.setting,'fore_odd');
  cid.defcolour:=$00000000;
  cid.order    :=3;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_dis);
  StrCopy(cid.setting,'back_dis');
  cid.defcolour:=$008080FF;
  cid.order    :=4;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_dis);
  StrCopy(cid.setting,'fore_dis');
  cid.defcolour:=$00000000;
  cid.order    :=5;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_del);
  StrCopy(cid.setting,'back_del');
  cid.defcolour:=$008000FF;
  cid.order    :=6;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_del);
  StrCopy(cid.setting,'fore_del');
  cid.defcolour:=$00000000;
  cid.order    :=7;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_hid);
  StrCopy(cid.setting,'back_hid');
  cid.defcolour:=$0080FFFF;
  cid.order    :=8;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_hid);
  StrCopy(cid.setting,'fore_hid');
  cid.defcolour:=$00000000;
  cid.order    :=9;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_meta);
  StrCopy(cid.setting,'back_meta');
  cid.defcolour:=$00BAE699;
  cid.order    :=10;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_meta);
  StrCopy(cid.setting,'fore_meta');
  cid.defcolour:=$00000000;
  cid.order    :=11;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,bkg_sub);
  StrCopy(cid.setting,'back_sub');
  cid.defcolour:=$00B3CCC1;
  cid.order    :=12;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);

  StrCopy(cid.name   ,fgr_sub);
  StrCopy(cid.setting,'fore_sub');
  cid.defcolour:=$00000000;
  cid.order    :=13;
  CallService(MS_COLOUR_REGISTERA,dword(@cid),0);
end;

function int2stra(i:integer):PAnsiChar;
var
  buf:array [0..31] of AnsiChar;
begin
  IntToStr(buf,i);
  StrDup(result,buf);
end;

function int2hexa(i:integer):PAnsiChar;
var
  buf:array [0..31] of AnsiChar;
begin
  IntToHex(buf,i);
  StrDup(result,buf);
end;

function int2strw(i:integer):PWideChar;
var
  buf:array [0..31] of WideChar;
begin
  IntToStr(buf,i);
  StrDupW(result,buf);
end;

function int2hexw(i:integer):PWideChar;
var
  buf:array [0..31] of WideChar;
begin
  IntToHex(buf,i);
  StrDupW(result,buf);
end;

function BuildLastSeenTime(cont:THANDLE;modulename:PAnsiChar):PWideChar;
var
  vars:array [0..4] of integer;
begin
  vars[2]:=DBReadWord(cont,modulename,'Year',0);
  if vars[2]<>0 then
  begin
    mGetMem(result,20*SizeOf(WideChar));
    vars[1]:=DBReadWord(cont,modulename,'Month'  ,0);
    vars[0]:=DBReadWord(cont,modulename,'Day'    ,0);
    vars[3]:=DBReadWord(cont,modulename,'Hours'  ,0);
    vars[4]:=DBReadWord(cont,modulename,'Minutes',0);
    if IsAnsi then
      wvsprintfa(pAnsiChar(result),'%.2u.%.2u.%.4u - %.2u:%.2u',@vars)
    else
      wvsprintfw(result,'%.2u.%.2u.%.4u - %.2u:%.2u',@vars);
  end
  else
    result:=nil;
end;

function BuildLastSeenTimeInt(cont:thandle;modulename:PAnsiChar):cardinal;
var
  Day,Month,Year,Hours,Minutes:word;
begin
  Year:=DBReadWord(cont,modulename,'Year',0);
  if Year<>0 then
  begin
    Month  :=DBReadWord(cont,modulename,'Month'  ,0);
    Day    :=DBReadWord(cont,modulename,'Day'    ,0);
    Hours  :=DBReadWord(cont,modulename,'Hours'  ,0);
    Minutes:=DBReadWord(cont,modulename,'Minutes',0);
    result:=Minutes+Hours*60+Day*60*24+Month*60*24*31+(Year-1980)*60*24*31*356; // was 366
  end
  else
    result:=0;
end;

function IPtoStr(ip:dword):PWideChar;
var
  buf:array [0..16] of WideChar;
  p:PWideChar;
begin
  p:=buf;
  IntToStr(buf,ip shr 24);
  while p^<>#0 do inc(p); p^:='.'; inc(p);
  IntToStr(p,(ip shr 16) and $FF);
  while p^<>#0 do inc(p); p^:='.'; inc(p);
  IntToStr(p,HI(ip));
  while p^<>#0 do inc(p); p^:='.'; inc(p);
  IntToStr(p,LO(ip));
  if IsAnsi then
    FastWideToAnsi(buf,pAnsiChar(result))
  else
    StrDupW(result,buf);
end;

function TimeToStrW(data:dword):PWideChar;
var
  strdatetime:array [0..63] of WideChar;
  dbtts:TDBTIMETOSTRING;
begin
  dbtts.cbDest    :=sizeof(strdatetime);
  dbtts.szDest.w  :=@strdatetime;
  dbtts.szFormat.w:='d - t';
  PluginLink^.CallService(MS_DB_TIME_TIMESTAMPTOSTRINGT,data,integer(@dbtts));
  StrDupW(result,strdatetime);
end;

function TimeToStrA(data:dword):PAnsiChar;
var
  strdatetime:array [0..63] of AnsiChar;
  dbtts:TDBTIMETOSTRING;
begin
  dbtts.cbDest    :=sizeof(strdatetime);
  dbtts.szDest.a  :=@strdatetime;
  dbtts.szFormat.a:='d - t';
  PluginLink^.CallService(MS_DB_TIME_TIMESTAMPTOSTRING,data,integer(@dbtts));
  StrDup(result,strdatetime);
end;

function FindMeta(hMeta:THANDLE;var MetaNum:dword):dword;
var
  i:integer;
begin
  result:=0;
  for i:=0 to HIGH(FlagBuf) do
  begin
    with FlagBuf[i] do
    begin
      if contact=hMeta then
      begin
        if wparam=0 then // new meta
        begin
          inc(LastMeta);
          wparam :=LastMeta;
          lparam :=0;
        end;
        MetaNum:=wparam;
        inc(lparam);
        result:=lparam;
        break;
      end;
    end;
  end;
end;

function DoMeta(hContact:THANDLE):pointer;
var
  pc:pAnsiChar;
  pw:pWideChar;
  i:integer;
begin
  result:=nil;
  for i:=0 to HIGH(FlagBuf) do
  begin
    with FlagBuf[i] do
    begin
      if contact=hContact then
      begin
        if (flags and QSF_META)<>0 then // adding new meta count
        begin
          if wparam=0 then
          begin
            inc(LastMeta);
            wparam:=LastMeta;
//            lparam:=0;
          end;
        end
        else if (flags and QSF_SUBMETA)<>0 then
        begin
          lparam:=FindMeta(CallService(MS_MC_GETMETACONTACT,hContact,0),wparam);
        end;

        if wparam>0 then
        begin
          mGetMem(result,32);
          if IsAnsi then
          begin
            pc:=result;
            pc[0]:='[';
            IntToStr(pc+1,wparam,3);
            pc[4]:=']';
            if lparam>0 then
            begin
              pc[5]:=' ';
              IntToStr(pc+6,lparam);
            end
            else
              pc[5]:=#0;
          end
          else
          begin
            pw:=result;
            pw[0]:='[';
            IntToStr(pw+1,wparam,3);
            pw[4]:=']';
            if lparam>0 then
            begin
              pw[5]:=' ';
              IntToStr(pw+6,lparam);
            end
            else
              pw[5]:=#0;
          end;
        end;
        break;
      end;
    end;
  end;
end;

procedure LoadOneItem(hContact:THANDLE;num:integer;proto:PAnsiChar; var res:QSRec);
var
  cni:TCONTACTINFO;
  dbei:TDBEVENTINFO;
  hDBEvent:cardinal;
  tmp:dword;
  protov:PAnsiChar;
begin
  FillChar(res,SizeOf(QSRec),0);
  res.data:=dword(-1);
  res.text:=nil;
  with qsopt.columns[num] do
  begin

    if module_name<>nil then
      protov:=module_name
    else
      protov:=proto;

    case setting_type of
      ST_METACONTACT: begin
        res.text:=DoMeta(hContact);
      end;

      ST_SCRIPT: begin
        if isAnsi then
          pAnsiChar(res.text):=ParseVarString(wparam.a,hContact)
        else
          res.text:=ParseVarString(wparam.w,hContact);
      end;

      ST_SERVICE: begin
        if wparam._type=ptCurrent then wparam.n:=hContact;
        if lparam._type=ptCurrent then lparam.n:=hContact;
        tmp:=PluginLink^.CallService(protov,wparam.n,lparam.n);
        if tmp=CALLSERVICE_NOTFOUND then exit;
        case setting_cnftype of
          ptString: begin
            if IsAnsi then
              StrDup(pAnsiChar(res.text),pAnsiChar(tmp))
            else
              AnsiToWide(PAnsiChar(tmp),res.text);
          end;
          ptUnicode: begin
            StrDupW(res.text,PWideChar(tmp));
          end;
          ptNumber,ptInteger:begin
            res.data:=tmp;
            if IsAnsi then
              res.text:=pWideChar(int2stra(tmp))
            else
              res.text:=int2strw(tmp);
          end;
        end;
      end;

      ST_CONTACTINFO: begin
        FillChar(cni,SizeOf(cni),0);
        cni.cbSize  :=sizeof(cni);
        if IsAnsi then
          cni.dwFlag:=setting_cnftype
        else
          cni.dwFlag:=setting_cnftype or CNF_UNICODE;
        cni.hContact:=hContact;
        cni.szProto :=proto;
        if PluginLink^.CallService(MS_CONTACT_GETCONTACTINFO,0,integer(@cni))=0 then
        begin
          case cni._type of
            CNFT_ASCIIZ: begin
              if cni.retval.szVal.w<>nil then
              begin
                if IsAnsi then
                  StrDup(pAnsiChar(res.text),cni.retval.szVal.a)
                else
                  StrDupW(res.text,cni.retval.szVal.w);
                mmi.free(cni.retval.szVal.w);
              end;
              exit;
            end;
            CNFT_BYTE :begin
              res.data:=cni.retval.bVal;
              if setting_cnftype=CNF_GENDER then
              begin
                if not (res.data in [70,77]) then
                  res.data:=DBReadByte(hContact,'UserInfo','Gender',0);
                exit;
              end
            end;
            CNFT_WORD :res.data:=cni.retval.wVal;
            CNFT_DWORD:res.data:=cni.retval.dVal;
          end;
          if IsAnsi then
            res.text:=pWideChar(int2stra(res.data))
          else
            res.text:=int2strw(res.data);
        end;
      end;

      ST_STRING: begin
        if IsAnsi then
          res.text:=PWideChar(DBReadString(hContact,protov,wparam.a,nil))
        else
          res.text:=DBReadUnicode(hContact,protov,wparam.a,nil)
      end;

      ST_BYTE: begin
        res.data:=DBReadByte(hContact,protov,wparam.a,0);
          if IsAnsi then
            res.text:=pWideChar(int2stra(res.data))
          else
            res.text:=int2strw(res.data);
      end;

      ST_WORD: begin
        res.data:=DBReadWord(hContact,protov,wparam.a,0);
          if IsAnsi then
            res.text:=pWideChar(int2stra(res.data))
          else
            res.text:=int2strw(res.data);
      end;

      ST_INT: begin
        if (module_name=nil) and (wparam.a=nil) then
        begin
          res.data:=hContact;
          if IsAnsi then
            res.text:=pWideChar(int2hexa(res.data))
          else
            res.text:=int2hexw(res.data);
        end
        else
        begin
          res.data:=DBReadDWord(hContact,protov,wparam.a,0);
          if IsAnsi then
            res.text:=pWideChar(int2stra(res.data))
          else
            res.text:=int2strw(res.data);
        end;
      end;

      ST_LASTSEEN: begin
        res.data:=BuildLastSeenTimeInt(hContact,protov);
        res.text:=BuildLastSeenTime   (hContact,protov);
      end;

      ST_IP: begin
        res.data:=DBReadDWord(hContact,protov,wparam.a,0);
        res.text:=IPtoStr(res.data);
      end;

      ST_TIMESTAMP: begin
        res.data:=DBReadDWord(hContact,protov,wparam.a,0);
        if res.data<>0 then
          if IsAnsi then
            res.text:=pWideChar(TimeToStrA(res.data))
          else
            res.text:=TimeToStrW(res.data);
      end;

      ST_LASTEVENT: begin
        hDbEvent:=PluginLink^.CallService(MS_DB_EVENT_FINDLAST,hContact,0);
        if hDbEvent<>0 then
        begin
          ZeroMemory(@dbei,sizeof(dbei));
          dbei.cbSize:=SizeOf(dbei);
          PluginLink^.CallService(MS_DB_EVENT_GET,hDbEvent,integer(@dbei));
          res.data:=dbei.timestamp;
          if IsAnsi then
            res.text:=pWideChar(TimeToStrA(res.data))
          else
            res.text:=TimeToStrW(res.data);
        end
        else
          res.data:=0;
      end;
    end;
  end;
end;

function CompareItem(lParam1,lParam2:Cardinal;SortType:integer):integer; stdcall;
var
  typ1,typ2:boolean;
  res1,res2:PQSRec;
  i1,i2:dword;
begin
  result:=0;
  if SortType=StatusSort then //sort by status
  begin
    i1:=FlagBuf[lParam1].status;
    i2:=FlagBuf[lParam2].status;
    // offline - to the end
    if i1=ID_STATUS_OFFLINE then i1:=ID_STATUS_OFFLINE+64;
    if i2=ID_STATUS_OFFLINE then i2:=ID_STATUS_OFFLINE+64;
    // not string parameters
    typ1:=false;
    typ2:=false;
  end
  else
  begin
    res1:=@MainBuf[lParam1,SortType];
    res2:=@MainBuf[lParam2,SortType];
    i1  := res1^.data;
    i2  := res2^.data;
    typ1:=i1=dword(-1);
    typ2:=i2=dword(-1);
    
    if (typ1 and typ2) then // string & string
    begin
      if (res2.text=nil) and (res1.text=nil) then // nil
        result:=0
      else if res2.text=nil then
        result:=1
      else if res1.text=nil then
        result:=-1
      else
        if IsAnsi then
          result:=lstrcmpia(pAnsiChar(res1.text),pAnsiChar(res2.text))
        else
          result:=lstrcmpiw(res1.text,res2.text);
    end
    else if typ1 or typ2 then // string & num
    begin
      if typ1 then
        result:=1
      else
        result:=-1;
    end;
  end;
  if not (typ1 or typ2) then // not strings
  begin
    if i1>i2 then
      result:=1
    else if i1<i2 then
      result:=-1
    else
      result:=0;
  end;
  if not qsopt.ascendsort then
    result:=-result;
end;

function FindBufNumber(hContact:THANDLE):integer;
var
  i:integer;
begin
  for i:=0 to HIGH(FlagBuf) do
  begin
    if FlagBuf[i].contact=hContact then
    begin
      result:=i;
      exit;
    end;
  end;
  result:=-1;
end;

function FindItem(num:integer):integer;
var
  fi:LV_FINDINFO;
begin
  if num>=0 then
  begin
    FillChar(fi,SizeOf(fi),0);
    fi.flags :=LVFI_PARAM;
    fi.lParam:=num;
    result:=SendMessage(grid,LVM_FINDITEM,-1,dword(@fi));
  end
  else
    result:=num;
end;

procedure AddContactToList(hContact:THANDLE;num:integer);
var
  i:integer;
  li:LV_ITEMW;
begin
  FillChar(li,SizeOf(li),0);
  li.iItem :=100000; //!! need append
  li.mask  :=LVIF_IMAGE or LVIF_PARAM;
  li.iImage:=PluginLink^.CallService(MS_CLIST_GETCONTACTICON,hContact,0);
  li.lParam:=num;
  if IsAnsi then
    li.iItem :=SendMessageA(grid,LVM_INSERTITEMA,0,integer(@li))
  else
    li.iItem :=SendMessageW(grid,LVM_INSERTITEMW,0,integer(@li));

  li.iImage:=0;
  for i:=0 to qsopt.numcolumns-1 do
  begin
    if (qsopt.columns[i].flags and COL_ON)<>0 then
    begin
      // Client icons preprocess
      li.pszText :=MainBuf[num,i].text;
      if (((qsopt.columns[i].flags and COL_CLIENT)<>0) and
         (li.pszText<>NIL) and qsopt.showclienticons) OR
         ((qsopt.columns[i].flags and (COL_XSTATUS or COL_GENDER))<>0) then
        li.mask:=LVIF_IMAGE or LVIF_TEXT
      else
        li.mask:=LVIF_TEXT;
      li.iSubItem:=colorder[i];
      if IsAnsi then
        SendMessageA(grid,LVM_SETITEMA,0,integer(@li))
      else
        SendMessageW(grid,LVM_SETITEMW,0,integer(@li));
    end;
  end;
end;

type
  pSBData = ^tSBData;
  tSBData = array [0..63] of record
    flags :cardinal;
    name  :PAnsiChar;
    total :cardinal; // in clist
    found :cardinal; // by pattern
    online:cardinal; // clist online
    liston:cardinal; // pattern online
  end;

procedure DrawSBA(const SBData:tSBData;protocnt:integer);
var
  aPartPos:array [0..63 ] of integer;
  buf     :array [0..255] of AnsiChar;
  fmtstr  :array [0..255] of AnsiChar;
  vars    :array [0..6  ] of integer;
  all:integer;
  i,j:integer;
  p:PAnsiChar;
  rc:TRECT;
  dc:HDC;
  icon:HICON;
begin
  StrCopy(@fmtstr,Translate('%u users found (%u) Online: %u'));
  vars[0]:=SBData[0].found;
  vars[1]:=Length(FlagBuf);
  vars[2]:=SBData[0].online;
  wvsprintfa(buf,fmtstr,@vars);
  dc:=GetDC(StatusBar);
  DrawTextA(dc,PAnsiChar(@buf),-1,rc,DT_CALCRECT);
  ReleaseDC(StatusBar,dc);
  all:=rc.right-rc.left;
  aPartPos[0]:=all;
  i:=1;
  while i<=protocnt do
  begin
    inc(all,55);
    aPartPos[i]:=all;
    inc(i);
  end;
  aPartPos[i]:=-1;
  SendMessageA(StatusBar,SB_SETPARTS,protocnt+2,dword(@aPartPos));
  SendMessageA(StatusBar,SB_SETTEXTA,0,dword(@buf));

  vars[4]:=dword(Translate('Online'));
  i:=protocnt;
  while i>0 do
  begin

    if (SBData[i].name=nil) or
      ((SBData[i].flags and (QSF_ACCDEL or QSF_ACCOFF))<>0) then
    begin
      icon:=PluginLink^.CallService(MS_SKIN_LOADPROTOICON,0,ID_STATUS_OFFLINE);
    end
    else
    begin
      icon:=PluginLink^.CallService(
          MS_SKIN_LOADPROTOICON,dword(SBData[i].name),ID_STATUS_ONLINE);
    end;

    if SBData[i].name=nil then
      vars[0]:=dword(Translate('Unknown'))
    else
      vars[0]:=dword(SBData[i].name);

    SendMessageA(StatusBar,SB_SETICON,i,icon);
    j:=High(buf);//(SizeOf(buf) div SizeOf(WideChar))-1;
    buf[j]:=#0;

    p:=@buf[0];
    while j>0 do
    begin
      dec(j);
      p^:=' ';
      inc(p);
    end;

    if (SBData[i].flags and QSF_ACCDEL)<>0 then
    begin
      buf [0]:='!';
      vars[1]:=dword(Translate('deleted'));
    end
    else if (SBData[i].flags and QSF_ACCOFF)<>0 then
    begin
      buf [0]:='?';
      vars[1]:=dword(Translate('off'));
    end
    else
      vars[1]:=dword(Translate('active'));

    IntToStr(pAnsiChar(@buf[2]),SBData[i].found);
    StrEnd(buf)^:=' ';
    SendMessageA(StatusBar,SB_SETTEXTA,i,dword(@buf));

// create tooltip
    with SBData[i] do
    begin
      vars[2]:=found;
      vars[3]:=total;
      vars[5]:=liston;
      vars[6]:=online;
    end;
    wvsprintfa(buf,'%s (%s): %u (%u); %s %u (%u)',@vars);
    SendMessageA(StatusBar,SB_SETTIPTEXTA,i,dword(@buf));
    dec(i);
  end;

end;

procedure DrawSBW(const SBData:tSBData; protocnt:integer);
var
  aPartPos:array [0..63 ] of integer;
  buf     :array [0..255] of WideChar;
  fmtstr  :array [0..255] of WideChar;
  vars    :array [0..6  ] of integer;
  all:integer;
  i,j:integer;
  p:PWideChar;
  rc:TRECT;
  dc:HDC;
  icon:HICON;
begin
  StrCopyW(@fmtstr,TranslateW('%u users found (%u) Online: %u'));
  vars[0]:=SBData[0].found;
  vars[1]:=Length(FlagBuf);
  vars[2]:=SBData[0].online;
  wvsprintfw(buf,fmtstr,@vars);
  dc:=GetDC(StatusBar);
  DrawTextW(dc,pWidechar(@buf),-1,rc,DT_CALCRECT);
  ReleaseDC(StatusBar,dc);
  all:=rc.right-rc.left;
  aPartPos[0]:=all;
  i:=1;
  while i<=protocnt do
  begin
    inc(all,55);
    aPartPos[i]:=all;
    inc(i);
  end;
  aPartPos[i]:=-1;
  SendMessageW(StatusBar,SB_SETPARTS,protocnt+2,dword(@aPartPos));
  SendMessageW(StatusBar,SB_SETTEXTW,0,dword(@buf));

  vars[4]:=dword(TranslateW('Online'));
  i:=protocnt;
  while i>0 do
  begin

    if (SBData[i].name=nil) or
      ((SBData[i].flags and (QSF_ACCDEL or QSF_ACCOFF))<>0) then
    begin
      icon:=PluginLink^.CallService(MS_SKIN_LOADPROTOICON,0,ID_STATUS_OFFLINE);
    end
    else
    begin
      icon:=PluginLink^.CallService(
          MS_SKIN_LOADPROTOICON,dword(SBData[i].name),ID_STATUS_ONLINE);
    end;

    if SBData[i].name=nil then
      vars[0]:=dword(TranslateW('Unknown'))
    else
    begin
      FastAnsiToWideBuf(SBData[i].name,fmtstr);
      PWideChar(vars[0]):=@fmtstr;
    end;

    SendMessageW(StatusBar,SB_SETICON,i,icon);

    j:=High(buf);//(SizeOf(buf) div SizeOf(WideChar))-1;
    buf[j]:=#0;

    p:=@buf[0];
    while j>0 do
    begin
      dec(j);
      p^:=' ';
      inc(p);
    end;

    if (SBData[i].flags and QSF_ACCDEL)<>0 then
    begin
      buf [0]:='!';
      vars[1]:=dword(TranslateW('deleted'));
    end
    else if (SBData[i].flags and QSF_ACCOFF)<>0 then
    begin
      buf [0]:='?';
      vars[1]:=dword(TranslateW('off'));
    end
    else
      vars[1]:=dword(TranslateW('active'));

    IntToStr(pWideChar(@buf[2]),SBData[i].found);
    StrEndW(buf)^:=' ';
    SendMessageW(StatusBar,SB_SETTEXTW,i,dword(@buf));

// create tooltip
    with SBData[i] do
    begin
      vars[2]:=found;
      vars[3]:=total;
      vars[5]:=liston;
      vars[6]:=online;
    end;
    wvsprintfw(buf,'%s (%s): %u (%u); %s %u (%u)',@vars);
    SendMessageW(StatusBar,SB_SETTIPTEXTW,i,dword(@buf));
    dec(i);
  end;
  
end;

procedure UpdateSB;
var
  protocnt:integer;
  SBData: tSBData;
  i,j:integer;
  p:pQSFRec;
begin
  FillChar(SBData,SizeOf(SBData),0);
  protocnt:=0;

  for j:=0 to HIGH(FlagBuf) do
  begin

    p:=@FlagBuf[j];
    if protocnt>0 then
    begin
      i:=protocnt;
      while i>0 do
      begin
        if StrCmp(SBData[i].name,p^.proto)=0 then
          break;
        dec(i);
      end;
    end
    else
      i:=0;

    if i=0 then // no known proto
    begin
      if protocnt<63 then
      begin
        inc(protocnt);
        i:=protocnt;
        SBData[protocnt].name :=p.proto;
        SBData[protocnt].flags:=p.flags;
      end
      else ; //!! error
    end;

    inc(SBData[i].total);

    if (p^.flags and QSF_ACTIVE)<>0 then
    begin
      inc(SBData[i].found);
      inc(SBData[0].found);
    end;

    if p^.status<>ID_STATUS_OFFLINE then
    begin
      inc(SBData[i].online);
      inc(SBData[0].online);
      if (p^.flags and QSF_ACTIVE)<>0 then
      begin
        inc(SBData[i].liston);
        inc(SBData[0].liston);
      end;
    end;

  end;

  if IsAnsi then
    DrawSBA(SBData,protocnt)
  else
    DrawSBW(SBData,protocnt);
end;

procedure Sort;
begin
  if qsopt.columnsort>=tablecolumns then
    qsopt.columnsort:=StatusSort;

  ListView_SortItems(grid,@CompareItem,GetQSColumn(qsopt.columnsort));

  if (qsopt.columnsort<>StatusSort) and qsopt.sortbystatus then
    ListView_SortItems(grid,@CompareItem,StatusSort);
end;

procedure MakePatternA;
var
  wasquote:bool;
  lpatptr:PAnsiChar;
begin
  numpattern:=0;
  if (pattern<>nil) and (pattern^<>#0) then
  begin
    wasquote:=false;
    mFreeMem(patstr);
    StrDup(pAnsiChar(patstr),pAnsiChar(pattern));
    lpatptr:=pAnsiChar(patstr);
    repeat
      while lpatptr^=' ' do inc(lpatptr);
      if lpatptr^<>#0 then
      begin
        if lpatptr^='"' then
        begin
          inc(lpatptr);
          wasquote:=true;
        end
        else
        begin
          patterns[numpattern].str:=pWideChar(lpatptr);
          inc(numpattern);
          while lpatptr^<>#0 do
          begin
            if wasquote then
            begin
              if lpatptr^='"' then
              begin
                wasquote:=false;
                break;
              end;
            end
            else if lpatptr^=' ' then
              break;
            inc(lpatptr);
          end;
          if lpatptr^<>#0 then
          begin
            lpatptr^:=#0;
            inc(lpatptr);
          end;
        end;
        if numpattern=maxpattern then break;
      end;
    until lpatptr^=#0;
  end
  else
  begin
    mFreeMem(patstr);
  end;
end;

procedure MakePatternW;
var
  wasquote:bool;
  lpatptr:PWideChar;
begin
  numpattern:=0;
  if (pattern<>nil) and (pattern^<>#0) then
  begin
    wasquote:=false;
    mFreeMem(patstr);
    StrDupW(patstr,pattern);
    lpatptr:=patstr;
    repeat
      while lpatptr^=' ' do inc(lpatptr);
      if lpatptr^<>#0 then
      begin
        if lpatptr^='"' then
        begin
          inc(lpatptr);
          wasquote:=true;
        end
        else
        begin
          patterns[numpattern].str:=lpatptr;
          inc(numpattern);
          while lpatptr^<>#0 do
          begin
            if wasquote then
            begin
              if lpatptr^='"' then
              begin
                wasquote:=false;
                break;
              end;
            end
            else if lpatptr^=' ' then
              break;
            inc(lpatptr);
          end;
          if lpatptr^<>#0 then
          begin
            lpatptr^:=#0;
            inc(lpatptr);
          end;
        end;
        if numpattern=maxpattern then break;
      end;
    until lpatptr^=#0;
  end
  else
  begin
    mFreeMem(patstr);
  end;
end;

function CheckPatternA(cnt:integer):boolean;
var
  lstr:array [0..1023] of AnsiChar;
  i,j:integer;
begin
  if numpattern>0 then
  begin
    for i:=0 to numpattern-1 do
      patterns[i].res:=false;

    for i:=0 to qsopt.numcolumns-1 do
    begin
      if ((qsopt.columns[i].flags and COL_ON)<>0) and
         (MainBuf[cnt,i].text<>nil) then
      begin
        StrCopy(lstr,pAnsiChar(MainBuf[cnt,i].text),HIGH(lstr));
        CharLowerA(lstr);
        for j:=0 to numpattern-1 do
          if not patterns[j].res then
          begin
            if StrPos(lstr,pAnsiChar(patterns[j].str))<>nil then //!!
              patterns[j].res:=true;
          end;
      end;
    end;

    result:=true;
    for i:=0 to numpattern-1 do
      result:=result and patterns[i].res;
  end
  else
    result:=true;
end;

function CheckPatternW(cnt:integer):boolean;
var
  lstr:array [0..1023] of WideChar;
  i,j:integer;
begin
  if numpattern>0 then
  begin
    for i:=0 to numpattern-1 do
      patterns[i].res:=false;

    for i:=0 to qsopt.numcolumns-1 do
    begin
      if ((qsopt.columns[i].flags and COL_ON)<>0) and
         (MainBuf[cnt,i].text<>nil) then
      begin
        StrCopyW(lstr,MainBuf[cnt,i].text,HIGH(lstr));
        CharLowerW(lstr);
        for j:=0 to numpattern-1 do
          if not patterns[j].res then
          begin
            if StrPosW(lstr,patterns[j].str)<>nil then //!!
              patterns[j].res:=true;
          end;
      end;
    end;

    result:=true;
    for i:=0 to numpattern-1 do
      result:=result and patterns[i].res;
  end
  else
    result:=true;
end;

procedure ProcessLine(num:integer;test:boolean=true);
var
  p:pQSFRec;
  l:boolean;
begin
  p:=@FlagBuf[num];
  if (p^.flags and QSF_DELETED)<>0 then
    exit;

  if qsopt.showonlyinlist then
  begin
    if (p^.flags and QSF_INLIST)=0 then
      exit;
  end;

  if test then
  begin
    if IsAnsi then
      l:=CheckPatternA(num)
    else
      l:=CheckPatternW(num);
    if l then
      p^.flags:=p^.flags or QSF_PATTERN
    else
      p^.flags:=p^.flags and not QSF_PATTERN;
  end
  else
    l:=(p^.flags and QSF_PATTERN)<>0;//true;

  if l then
  begin
    if (p^.flags and QSF_ACTIVE)=0 then
    begin
      if (qsopt.showoffline) or (p^.status<>ID_STATUS_OFFLINE) then
      begin
        p^.flags:=p^.flags or QSF_ACTIVE;
        AddContactToList(p^.contact,num);
      end;
    end
  end
  else
  begin
    if (p^.flags and QSF_ACTIVE)<>0 then
    begin
      p^.flags:=p^.flags and not QSF_ACTIVE;
      ListView_DeleteItem(grid,FindItem(num));
    end;
  end;
end;

//!!
function ShowHideOffline(show:boolean):integer;
var
  p:pQSFRec;
  i:integer;
begin
  result:=0;

  SendMessage(grid,WM_SETREDRAW,0,0);

  for i:=0 to HIGH(FlagBuf) do
  begin
    p:=@FlagBuf[i];
    if (p^.status=ID_STATUS_OFFLINE) and ((p^.flags and QSF_PATTERN)<>0) then
    begin
      if show then
      begin
        p^.flags:=p^.flags or QSF_ACTIVE;
        AddContactToList(p^.contact,i);
      end
      else if (p^.flags and QSF_ACTIVE)<>0 then
      begin
        p^.flags:=p^.flags and not QSF_ACTIVE;
        ListView_DeleteItem(grid,FindItem(i));
      end;

      if (p^.flags and QSF_ACTIVE)=0 then
      begin
        if show then ProcessLine(i,false)
      end
      else if not show then
      begin
        p^.flags:=p^.flags and not QSF_ACTIVE;
        ListView_DeleteItem(grid,FindItem(i));
      end;
    end;
  end;
  
  SendMessage(grid,WM_SETREDRAW,1,0);
  InvalidateRect(grid,nil,false);

  Sort;
  UpdateSB;
end;

procedure FillGrid;
var
  cnt:integer;
begin

  SendMessage(grid,WM_SETREDRAW,0,0);

  if IsAnsi then
    MakePatternA
  else
    MakePatternW;

  for cnt:=0 to HIGH(FlagBuf) do
    ProcessLine(cnt);

  SendMessage(grid,WM_SETREDRAW,1,0);
  InvalidateRect(grid,nil,false);

  Sort;
  UpdateSB;
  ListView_SetItemState(grid,0,LVIS_FOCUSED or LVIS_SELECTED,
    LVIS_FOCUSED or LVIS_SELECTED);
end;

procedure AddContact(num:integer;hContact:cardinal);
var
  i:integer;
begin
  FillChar(FlagBuf[num],SizeOf(QSFRec),0);
  with FlagBuf[num] do
  begin
    contact:=hContact;
    flags  :=0;
    i:=IsContactActive(hContact,proto);
    case i of
      -2: flags:=flags or QSF_ACCDEL;  // deleted account
      -1: flags:=flags or QSF_ACCOFF;  // disabled account
      0 : ; // hidden contact
      1 : flags:=flags or QSF_META;    // metacontact
      2 : flags:=flags or QSF_SUBMETA; // subMetacontact
    end;
    if i>0 then
      flags:=flags or QSF_INLIST;      // normal contact

    if (proto=nil) or (i<0) then
      status:=ID_STATUS_OFFLINE
    else
      status:=DBReadWord(contact,proto,'Status',ID_STATUS_OFFLINE);

    for i:=0 to qsopt.numcolumns-1 do
      if (qsopt.columns[i].flags and COL_ON)<>0 then
        LoadOneItem(contact,i,proto,MainBuf[num,i]);
  end;

end;

function PrepareToFill:boolean;
var
  cnt,cnt1:integer;
  hContact:cardinal;
  i:integer;
begin
  result:=false;
  if qsopt.numcolumns=0 then
    exit;
  // calculating contacts
  cnt:=PluginLink^.CallService(MS_DB_CONTACT_GETCOUNT,0,0);
  if cnt=0 then
    exit;

  result:=true;
  // Allocate mem
  SetLength(MainBuf,cnt,qsopt.numcolumns);
  SetLength(FlagBuf,cnt);

  // filling buffer
  LastMeta:=0;
  cnt1:=0;
  hContact:=PluginLink^.CallService(MS_DB_CONTACT_FINDFIRST,0,0);
  while hContact<>0 do
  begin
    //!! check account
    AddContact(cnt1,hContact);
    inc(cnt1);
    if cnt1=cnt then break; // additional checking
    hContact:=PluginLink^.CallService(MS_DB_CONTACT_FINDNEXT,hContact,0);
  end;
  if cnt1<>cnt then
  begin
    SetLength(MainBuf,cnt1);
    SetLength(FlagBuf,cnt1);
  end;

  SetLength(colorder,qsopt.numcolumns);
  cnt:=0;
  for i:=0 to qsopt.numcolumns-1 do
  begin
    if (qsopt.columns[i].flags and COL_ON)<>0 then
    begin
      colorder[i]:=cnt;
      inc(cnt);
      qsopt.columns[i].flags := qsopt.columns[i].flags or COL_INIT;
    end
    else
      colorder[i]:=-1;
  end;

end;

function GetFocusedhContact:THANDLE;
var
  i:integer;
begin
  i:=LV_GetLParam(grid);
  if i=-1 then
    result:=0
  else
    result:=FlagBuf[i].contact;
end;

procedure ShowContactMsgDlg(hContact:THANDLE);
begin
  if hContact<>0 then
  begin
    ShowContactDialog(hContact);
    if qsopt.closeafteraction then DestroyWindow(mainwnd);
  end;
end;

procedure DeleteOneContact(hContact:THANDLE);
begin
  if Pluginlink^.ServiceExists(strCListDel)>0 then
    PluginLink^.CallService(strCListDel,hContact,0)
  else
    PluginLink^.CallService(MS_DB_CONTACT_DELETE,hContact,0);
end;

procedure DeleteByList;
var
  i,j:integer;
begin
  j:=ListView_GetItemCount(grid)-1;

  if IsAnsi then
    i:=MessageBoxA(0,Translate('Do you really want to delete selected contacts?'),
       Translate('Warning'),MB_OKCANCEL+MB_ICONWARNING)
  else
    i:=MessageBoxW(0,TranslateW('Do you really want to delete selected contacts?'),
       TranslateW('Warning'),MB_OKCANCEL+MB_ICONWARNING);

  if i=IDOK then
  begin
    SendMessage(grid,WM_SETREDRAW,0,0);
    for i:=j downto 0 do
    begin
      if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
        PluginLink^.CallService(MS_DB_CONTACT_DELETE,FlagBuf[LV_GetLParam(grid,i)].contact,0);
    end;
    SendMessage(grid,WM_SETREDRAW,1,0);
  end;
end;

procedure ConvertToMeta;
var
  i,j:integer;
  hMeta:THANDLE;
  tmp:THANDLE;
begin
  j:=ListView_GetItemCount(grid)-1;

  hMeta:=0;
  for i:=j downto 0 do // check
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      tmp:=CallService(MS_MC_GETMETACONTACT,FlagBuf[LV_GetLParam(grid,i)].contact,0);
      if tmp<>0 then
        if hMeta=0 then
          hMeta:=tmp
        else if tmp<>hMeta then
        begin
          if IsAnsi then
            MessageBoxA(0,
              Translate('Some of selected contacts in different metacontacts already'),
              qs_name,MB_ICONERROR)
          else
            MessageBoxW(0,
              TranslateW('Some of selected contacts in different metacontacts already'),
              'Quick Search',MB_ICONERROR);
          exit;
        end;
    end;
  end;

  if hMeta<>0 then
  begin
    if IsAnsi then
      i:=MessageBoxA(0,
        Translate('One or more contacts in same Meta already. Try to convert anyway?'),
        qs_name,MB_YESNO+MB_ICONWARNING)
    else
      i:=MessageBoxW(0,
        TranslateW('One or more contacts in same Meta already. Try to convert anyway?'),
        'Quick Search',MB_YESNO+MB_ICONWARNING);
    if i<>IDYES then
      exit;
  end;

  // convert if needed
  for i:=j downto 0 do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      if hMeta=0 then
        hMeta:=CallService(MS_MC_CONVERTTOMETA,FlagBuf[LV_GetLParam(grid,i)].contact,0)
      else
        CallService(MS_MC_ADDTOMETA,FlagBuf[LV_GetLParam(grid,i)].contact,hMeta);
    end;
  end;
end;

procedure MoveToGroup(group:PWideChar);
var
  i,j,grcol:integer;
  contact:THANDLE;
begin
  j:=ListView_GetItemCount(grid)-1;
  grcol:=-1;
  for i:=0 to qsopt.numcolumns-1 do
  begin
    with qsopt.columns[i] do
      if (setting_type=ST_STRING) and
         (StrCmp(module_name,'CList')=0) and
         (StrCmp(wparam.a   ,'Group')=0) then
      begin
        if (flags and COL_ON)=0 then
          flags:=flags and not COL_INIT
        else
          grcol:=i;
        break;
      end
  end;
  for i:=0 to j do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      contact:=FlagBuf[LV_GetLParam(grid,i)].contact;
      if IsAnsi then //!!!!!
        DBWriteString(contact,strCList,'Group',pAnsiChar(group))
      else
        DBWriteUnicode(contact,strCList,'Group',group);
      if (not qsopt.closeafteraction) and (grcol>=0) then
      begin
         LoadOneItem(contact,grcol,nil,MainBuf[i,grcol]);
      end;
    end;
  end;
  if (not qsopt.closeafteraction) and (grcol>=0) then
    FillGrid;
end;

const
  ContactBufSize = 1024;

function IsColumnMinimized(num:integer):bool;
begin
  result:=ListView_GetColumnWidth(grid,num)<=10;
end;

procedure CopyMultiLinesA(num:integer);
var
  i,j,k:integer;
  p,buf:PAnsiChar;
  tmpcnt,cnt:integer;
begin
  cnt:=0;
  if qsopt.exportheaders then
  begin
    k:=0;
    while k<qsopt.numcolumns do
    begin
      if not (qsopt.skipminimized and IsColumnMinimized(k)) then
        inc(cnt,StrLen(Translate(pAnsiChar(qsopt.columns[k].title)))+1);
      Inc(k);
    end;
    if cnt>0 then
      inc(cnt,2);
  end;
  j:=ListView_GetItemCount(grid)-1;
  tmpcnt:=cnt;
  for i:=0 to j do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      k:=0;
      num:=LV_GetLParam(grid,i);
      while k<qsopt.numcolumns do
      begin
        if not (qsopt.skipminimized and IsColumnMinimized(k)) then
          inc(cnt,StrLen(pAnsiChar(MainBuf[num,k].text))+1);
        Inc(k);
      end;
    end;
    if tmpcnt<>cnt then
      inc(cnt,2);
  end;
  if cnt=0 then
    exit;

  inc(cnt);
  mGetMem(buf,cnt);
  p:=buf;

  if qsopt.exportheaders then
  begin
    k:=0;
    while k<qsopt.numcolumns do
    begin
      if not (qsopt.skipminimized and IsColumnMinimized(k)) then
      begin
        StrCopy(p,Translate(pAnsiChar(qsopt.columns[k].title)));
        p:=StrEnd(p);
        p^:=#9;
        inc(p);
      end;
      inc(k);
    end;
    (p-1)^:=#13;
    p^    :=#10;
    inc(p);
  end;
  for i:=0 to j do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      k:=0;
      num:=LV_GetLParam(grid,i);
      while k<qsopt.numcolumns do
      begin
        if not (qsopt.skipminimized and IsColumnMinimized(k)) then
        begin
          StrCopy(p,pAnsiChar(MainBuf[num,k].text));
          p:=StrEnd(p);
          p^:=#9;
          inc(p);
        end;
        inc(k);
      end;
      (p-1)^:=#13;
      p^    :=#10;
      inc(p);
    end;
  end;
  p^:=#0;
  CopyToClipboard(buf,true);
  mFreeMem(buf);
end;

procedure CopyMultiLinesW(num:integer);
var
  i,j,k:integer;
  p,buf:PWideChar;
  tmpcnt,cnt:integer;
begin
  cnt:=0;
  if qsopt.exportheaders then
  begin
    k:=0;
    while k<qsopt.numcolumns do
    begin
      if not (qsopt.skipminimized and IsColumnMinimized(k)) then
        inc(cnt,StrLenW(TranslateW(qsopt.columns[k].title))+1);
      Inc(k);
    end;
    if cnt>0 then
      inc(cnt,2);
  end;
  j:=ListView_GetItemCount(grid)-1;
  tmpcnt:=cnt;
  for i:=0 to j do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      k:=0;
      num:=LV_GetLParam(grid,i);
      while k<qsopt.numcolumns do
      begin
        if not (qsopt.skipminimized and IsColumnMinimized(k)) then
          inc(cnt,StrLenW(MainBuf[num,k].text)+1);
        Inc(k);
      end;
    end;
    if tmpcnt<>cnt then
      inc(cnt,2);
  end;
  if cnt=0 then
    exit;

  inc(cnt);
  mGetMem(buf,cnt*SizeOf(WideChar));
  p:=buf;

  if qsopt.exportheaders then
  begin
    k:=0;
    while k<qsopt.numcolumns do
    begin
      if not (qsopt.skipminimized and IsColumnMinimized(k)) then
      begin
        StrCopyW(p,TranslateW(qsopt.columns[k].title));
        p:=StrEndW(p);
        p^:=#9;
        inc(p);
      end;
      inc(k);
    end;
    (p-1)^:=#13;
    p^    :=#10;
    inc(p);
  end;
  for i:=0 to j do
  begin
    if ListView_GetItemState(grid,i,LVIS_SELECTED)<>0 then
    begin
      k:=0;
      num:=LV_GetLParam(grid,i);
      while k<qsopt.numcolumns do
      begin
        if not (qsopt.skipminimized and IsColumnMinimized(k)) then
        begin
          StrCopyW(p,MainBuf[num,k].text);
          p:=StrEndW(p);
          p^:=#9;
          inc(p);
        end;
        inc(k);
      end;
      (p-1)^:=#13;
      p^    :=#10;
      inc(p);
    end;
  end;
  p^:=#0;
  CopyToClipboard(buf,false);
  mFreeMem(buf);
end;

var
  HintWnd:HWND;

function NewLVProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):integer; stdcall;
const
  OldHItem   :integer=0;
  OldHSubItem:integer=0;
var
  buf :array [0..255] of WideChar; //!! for spec columns and patterns now only
  buf1:array [0..127] of AnsiChar;
  p,pp:PWideChar;
  pc,ppc:pAnsiChar;
  i,num,cnt:integer;
  pinfo:LV_HITTESTINFO;
  TI:TToolInfoW;
  ics:TICQ_CUSTOM_STATUS;

  info:TCLCINFOTIP;
//  qsr:QSRec;
  txt:pWideChar;
  tmpCursor:TPOINT;
begin
  result:=0;
  case hMessage of

    WM_DESTROY: begin
      if TTInstalled then
        KillTimer(Dialog,TIMERID_HOVER);
    end;

    WM_LBUTTONDBLCLK: begin
      ShowContactMsgDlg(GetFocusedhContact);
      exit;
    end;

    WM_CHAR: begin
      if wParam=27 then // ESC
      begin
        PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDCANCEL,0);
        exit;
      end;
      if IsAnsi then
      begin
        case wParam of
          1: begin
            ListView_SetItemState(grid,-1,LVIS_SELECTED,LVIS_SELECTED);
          end;
          3: begin
            i:=ListView_GetSelectedCount(grid);
            if (i>1) or qsopt.singlecsv then
            begin
              CopyMultiLinesA(i);
              exit;
            end;

            cnt:=0;
            num:=LV_GetLParam(grid,ListView_GetNextItem(grid,-1,LVNI_FOCUSED));
            i:=0;
            while i<qsopt.numcolumns do
            begin
              if not (qsopt.skipminimized and IsColumnMinimized(i)) then
              begin
                pc:=Translate(pAnsiChar(qsopt.columns[i].title));
                inc(cnt,StrLen(pc)+1);
                if (StrEnd(pc)-1)^<>':' then
                  inc(cnt);

                inc(cnt,StrLen(pAnsiChar(MainBuf[num,i].text))+2);
              end;
            end;
            if cnt=0 then
              exit;
            mGetMem(ppc,cnt+1);
            pc:=ppc;

            i:=0;
            while i<qsopt.numcolumns do
            begin
              if not (qsopt.skipminimized and IsColumnMinimized(i)) then
              begin
                StrCopy(pc,Translate(pAnsiChar(qsopt.columns[i].title)));
                pc:=StrEnd(pc);
                if (pc-1)^<>':' then
                begin
                  pc^:=':';
                  inc(pc);
                end;
                pc^:=' '; inc(pc);
                StrCopy(pc,pAnsiChar(MainBuf[num,i].text));
                pc:=StrEnd(pc);
                pc^:=#13; (pc+1)^:=#10; inc(pc,2);
              end;
            end;
            pc^:=#0;

            CopyToClipboard(ppc,true);
            mFreeMem(ppc);
            exit;
          end;
          8: begin
            if pattern<>nil then
            begin
              StrCopy(pAnsiChar(@buf),pAnsiChar(pattern));
              pc:=StrEnd(pAnsiChar(@buf));
              (pc-1)^:=#0;
              SetDlgItemTextA(mainwnd,IDC_E_SEARCHTEXT,pAnsiChar(@buf));
            end;
          end;
          32..127: begin
            if pattern<>nil then
              StrCopy(pAnsiChar(@buf),pAnsiChar(pattern))
            else
              buf[0]:=#0;
            pc:=StrEnd(pAnsiChar(@buf));
            pc^:=AnsiChar(wParam);
            (pc+1)^:=#0;
            SetDlgItemTextA(mainwnd,IDC_E_SEARCHTEXT,pAnsiChar(@buf));
          end;
        end;
      end
      else
      begin
        case wParam of
          1: begin
            ListView_SetItemState(grid,-1,LVIS_SELECTED,LVIS_SELECTED);
          end;
          3: begin
            i:=ListView_GetSelectedCount(grid);
            if (i>1) or qsopt.singlecsv then
            begin
              CopyMultiLinesW(i);
              exit;
            end;

            cnt:=0;
            num:=LV_GetLParam(grid,ListView_GetNextItem(grid,-1,LVNI_FOCUSED));
            i:=0;
            while i<qsopt.numcolumns do
            begin
              if not (qsopt.skipminimized and IsColumnMinimized(i)) then
              begin
                p:=TranslateW(qsopt.columns[i].title);
                inc(cnt,StrLenW(p)+1);
                if (StrEndW(p)-1)^<>':' then
                  inc(cnt);

                inc(cnt,StrLenW(MainBuf[num,i].text)+2);
              end;
            end;
            if cnt=0 then
              exit;
            mGetMem(pp,(cnt+1)*SizeOf(WideChar));
            p:=pp;

            i:=0;
            while i<qsopt.numcolumns do
            begin
              if not (qsopt.skipminimized and IsColumnMinimized(i)) then
              begin
                StrCopyW(p,TranslateW(qsopt.columns[i].title));
                p:=StrEndW(p);
                if (p-1)^<>':' then
                begin
                  p^:=':';
                  inc(p);
                end;
                p^:=' '; inc(p);
                StrCopyW(p,MainBuf[num,i].text);
                p:=StrEndW(p);
                p^:=#13; (p+1)^:=#10; inc(p,2);
              end;
            end;
            p^:=#0;
            
            CopyToClipboard(pp,false);
            mFreeMem(pp);
            exit;
          end;
          8: begin
            if pattern<>nil then
            begin
              StrCopyW(buf,pattern);
              p:=StrEndW(buf);
              (p-1)^:=#0;
              SetDlgItemTextW(mainwnd,IDC_E_SEARCHTEXT,buf);
            end;
          end;
          32..127: begin
            if pattern<>nil then
              StrCopyW(buf,pattern)
            else
              buf[0]:=#0;
            p:=StrEndW(buf);
            p^:=WideChar(wParam);
            (p+1)^:=#0;
            SetDlgItemTextW(mainwnd,IDC_E_SEARCHTEXT,buf);
          end;
        end;
      end
    end;

    WM_TIMER: begin
      if wParam=TIMERID_HOVER then
      begin
				KillTimer(Dialog,TIMERID_HOVER);
				if GetForegroundWindow<>MainWnd then exit;
        i:=LV_GetLParam(grid,OldHItem);
        FillChar(info,SizeOf(info),0);
        with info do
        begin
          cbSize    :=SizeOf(info);
          hItem     :=FlagBuf[i].contact;
          GetCursorPos(ptCursor);
          tmpCursor :=ptCursor;
{
          ptCursor.x:=loword(lParam);
          ptCursor.y:=hiword(lParam);
}
          SendMessage(grid,LVM_GETITEMRECT,OldHItem,dword(@rcItem));
          ScreenToClient(grid,tmpCursor);
          if not PtInRect(rcItem,tmpCursor) then exit;
        end;
//        mGetMem(txt,16384*SizeOf(WideChar));
        if IsAnsi then
        begin
{          pc:=pAnsiChar(txt);
          for cnt:=0 to HIGH(MainBuf[0]) do
          begin
            if (qsopt.columns[cnt].flags and COL_ON)=0 then
            begin
              LoadOneItem(info.hItem,cnt,FlagBuf[i].proto,qsr);
              if qsr.text<>nil then
              begin
                if pAnsiChar(qsr.text)^<>#0 then
                begin
//!! need: buffer free space check here

num:=StrLen(pAnsiChar(qsopt.columns[cnt].title))+StrLen(pAnsiChar(qsr.text))+4;
if (32768-num)>(pc-pAnsiChar(txt)) then
begin
                  pc:=StrCopyE(pc,pAnsiChar(qsopt.columns[cnt].title));
                  pc^:=':'; inc(pc); pc^:=' '; inc(pc);
                  pc:=StrCopyE(pc,pAnsiChar(qsr.text));
                  pc^:=#13; inc(pc); pc^:=#10; inc(pc);
end
else
begin
  mFreeMem(qsr.text);
  break;
end;
                end;
                mFreeMem(qsr.text);
              end;
            end;
          end;
          pc^:=#0;
}
          CallService(MS_TIPPER_SHOWTIP,dword(txt),dword(@info));
        end
        else
        begin
{
          p:=txt;
          for cnt:=0 to HIGH(MainBuf[0]) do
          begin
            if (qsopt.columns[cnt].flags and COL_ON)=0 then
            begin
              LoadOneItem(info.hItem,cnt,FlagBuf[i].proto,qsr);
              if qsr.text<>nil then
              begin
                if qsr.text^<>#0 then
                begin
//!! need: buffer free space check here
num:=StrLenW(qsopt.columns[cnt].title)+StrLenW(qsr.text)+4;
if (16384-num)>(p-txt) then
begin

                  p:=StrCopyEW(p,qsopt.columns[cnt].title);
                  p^:=':'; inc(p); p^:=' '; inc(p);
                  p:=StrCopyEW(p,qsr.text);
                  p^:=#13; inc(p); p^:=#10; inc(p);
end
else
begin
  mFreeMem(qsr.text);
  break;
end;
                end;
                mFreeMem(qsr.text);
              end;
            end;
          end;
          p^:=#0;
}
          CallService(MS_TIPPER_SHOWTIPW,0{dword(txt)},dword(@info));
        end;
//        mFreeMem(txt);
        TTShowed:=true;
      end;
    end;

    WM_MOUSEMOVE: begin
      pinfo.pt.x:=loword(lParam);
      pinfo.pt.y:=hiword(lParam);
      pinfo.flags:=0;
      if integer(SendMessage(grid,LVM_SUBITEMHITTEST,0,dword(@pinfo)))<>-1 then
      begin
        if (pinfo.iItem<>OldHItem) or (pinfo.iSubItem<>OldHSubItem) then
        begin
          OldHSubItem:=pinfo.iSubItem;
          OldHItem   :=pinfo.iItem;

          if TTInstalled then
          begin
            if TTShowed then
            begin
              TTShowed:=false;
              CallService(MS_TIPPER_HIDETIP,0,0);
            end;
            KillTimer(Dialog, TIMERID_HOVER);
            if OldHSubItem=0 then
            begin
              SetTimer(Dialog, TIMERID_HOVER, 450, nil);
              exit;
            end;
          end;
//!!
          with TI do
          begin
            cbSize:=SizeOf(TI);
            uFlags:=TTF_SUBCLASS+TTF_IDISHWND;
            hWnd  :=MainWnd;
            uId   :=Dialog;
            hInst :=0;
          end;

          OldHSubItem:=GetQSColumn(OldHSubItem);
          if (qsopt.columns[OldHSubItem].flags and
             (COL_XSTATUS or COL_GENDER))<>0 then
          begin
            i:=LV_GetLParam(grid,OldHItem);
//            TTShowed:=true;
            if (qsopt.columns[OldHSubItem].flags and COL_GENDER)<>0 then
            begin
              case MainBuf[i,OldHSubItem].data of
                77: TI.lpszText:=tstrMale;
                70: TI.lpszText:=tstrFemale;
              else
                TI.lpszText:=tstrUnknown;
              end;
            end
            else // if (qsopt.columns[OldHSubItem].flags and COL_XSTATUS)<>0 then
            begin
              if IsAnsi then
              begin
                StrCopy(pAnsiChar(@buf),pAnsiChar(MainBuf[i,OldHSubItem].text));
                ics.flags:=CSSF_DEFAULT_NAME or CSSF_MASK_NAME;
              end
              else
              begin
                StrCopyW(buf,MainBuf[i,OldHSubItem].text);
                ics.flags:=CSSF_DEFAULT_NAME or CSSF_MASK_NAME or CSSF_UNICODE;
              end;

              StrCopy(StrCopyE(buf1,FlagBuf[i].proto),PS_ICQ_GETCUSTOMSTATUSEX);

              i:=StrToInt(buf);
              ics.wParam:=@i;
              ics.cbSize:=SizeOf(ics);
              ics.szName.w:=@buf;

              CallService(buf1,0,dword(@ics));
              if IsAnsi then
                TI.lpszText:=pWideChar(Translate(@buf))
              else
                TI.lpszText:=TranslateW(@buf);
            end;
          end
          else
          begin
            TI.lpszText:=nil;
//            TTShowed:=false;
          end;
          if IsAnsi then
            SendMessageA(HintWnd,TTM_SETTOOLINFOA,0,DWORD(@TI))
          else
            SendMessageW(HintWnd,TTM_SETTOOLINFOW,0,DWORD(@TI));
        end
      end;
    end;

    WM_KEYUP: begin
      case wParam of
        VK_RETURN: begin
          if ListView_GetSelectedCount(grid)=1 then
            ShowContactMsgDlg(GetFocusedhContact);
          exit;
        end;
        VK_INSERT: begin
          PluginLink^.CallService(MS_FINDADDFINDADD,0,0);
          exit;
        end;
        VK_DELETE: begin
          lParam:=ListView_GetSelectedCount(grid);
          if lParam>1 then
            DeleteByList
          else if lParam=1 then
            DeleteOneContact(GetFocusedhContact);
          exit;
        end;
        VK_F5: begin
          PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDC_REFRESH,0);
          exit;
        end;
      end;
    end;

    WM_NOTIFY: begin
      if integer(PNMHdr(lParam)^.code)=HDN_ENDDRAG then
      begin
        ShiftColumns(PHDNotify(lParam)^.Item,PHDNotify(lParam)^.pitem^.iOrder);
      end;
    end;

  end;
  result:=CallWindowProc(OldLVProc,dialog,hMessage,wParam,lParam);
end;

procedure ColumnClick(wnd:HWND;num:integer);
var
  hdi:THDITEM;
  header:HWND;
begin
  zeromemory(@hdi,sizeof(hdi));
  hdi.mask:=HDI_BITMAP or HDI_FORMAT;
  hdi.fmt :=HDF_LEFT   or HDF_STRING;
  header:=ListView_GetHeader(wnd);
  SendMessage(header,HDM_SETITEM,qsopt.columnsort,dword(@hdi));

  if qsopt.columnsort<>num then
  begin
    qsopt.ascendsort:=true;
    qsopt.columnsort:=num;
  end
  else
    qsopt.ascendsort:=not qsopt.ascendsort;
  
  if qsopt.ascendsort then
    hdi.hbm:=sortcoldn
  else
    hdi.hbm:=sortcolup;
  hdi.fmt:=HDF_LEFT or HDF_BITMAP or HDF_BITMAP_ON_RIGHT or HDF_STRING;
  Header_SetItem(header,num,hdi);

  Sort;
end;

procedure MakeColumnMenu;
var
  menu:HMENU;
  flag,id:integer;
  pt:TPOINT;
begin
  menu:=CreatePopupMenu;
  if menu<>0 then
  begin
    if IsAnsi then
    begin
      for id:=0 to qsopt.numcolumns-1 do
      begin
        if (qsopt.columns[id].flags and COL_ON)<>0 then
          flag:=MF_CHECKED or MF_STRING
        else
          flag:=MF_UNCHECKED or MF_STRING;
        AppendMenuA(menu,flag,100+id,Translate(pAnsiChar(qsopt.columns[id].title)));
      end;
    end
    else
    begin
      for id:=0 to qsopt.numcolumns-1 do
      begin
        if (qsopt.columns[id].flags and COL_ON)<>0 then
          flag:=MF_CHECKED or MF_STRING
        else
          flag:=MF_UNCHECKED or MF_STRING;
        AppendMenuW(menu,flag,100+id,TranslateW(qsopt.columns[id].title));
      end;
    end;
    GetCursorPos(pt);
    id:=integer(TrackPopupMenu(menu,TPM_RETURNCMD+TPM_NONOTIFY,pt.x,pt.y,0,mainwnd,nil));
    if id>100 then
    begin
      dec(id,100);
      with qsopt.columns[id] do
      begin
        flags:=flags xor COL_ON;
        if (flags and COL_ON)<>0 then
          flag:=wcShow
        else
          flag:=wcHide;
      end;
      WndChangeColumns(flag,id);
      OptChangeColumns(wcShow,id,ord(flag=wcShow));
    end;
    DestroyMenu(menu);
  end;
end;

function NewLVHProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):integer; stdcall;
begin
  case hMessage of

    WM_RBUTTONUP: begin
      result:=0;
      exit;
    end;

    WM_RBUTTONDOWN: begin
      MakeColumnMenu;
{
      hti.point.x:=LOWORD(lParam);
      hti.point.y:=HIWORD(lParam);
      i:=SendMessage(Dialog,HDM_HITTEST,0,dword(@hti));
//      i:=SendMessage(Dialog,HDM_ORDERTOINDEX,i,0);
      oldw:=ListView_GetColumnWidth(grid,i);
      if oldw<>10 then
        oldw:=10
      else
        oldw:=LVSCW_AUTOSIZE;
      SendMessage(grid,LVM_SETCOLUMNWIDTH,i,oldw);
      exit;
}{
      x:=LOWORD(lParam);
      cnt:=0;
      for i:=0 to qsopt.numcolumns-1 do
      begin
        oldw:=ListView_GetColumnWidth(grid,i);
        inc(cnt,oldw);
        if x<cnt then
        begin
          if oldw<>10 then
            oldw:=10
          else
            oldw:=LVSCW_AUTOSIZE;
          SendMessage(grid,LVM_SETCOLUMNWIDTH,i,oldw);
          result:=0;
          exit;
        end;
      end;
}
    end;
  end;
  result:=CallWindowProc(OldProc,dialog,hMessage,wParam,lParam);
end;

procedure SetCellColor(lplvcd:PNMLVCUSTOMDRAW;idx:integer);
begin
  if qsopt.colorize then
  begin
    with FlagBuf[idx] do 
    begin
      if (flags and QSF_ACCDEL)<>0 then
      begin
        lplvcd^.clrTextBk:=cbkg_del; 
        lplvcd^.clrText  :=cfgr_del;
      end
      else if (flags and QSF_ACCOFF)<>0 then
      begin
        lplvcd^.clrTextBk:=cbkg_dis; 
        lplvcd^.clrText  :=cfgr_dis; 
      end
      else if (flags and QSF_META)<>0 then
      begin
        lplvcd^.clrTextBk:=cbkg_meta;
        lplvcd^.clrText  :=cfgr_meta;
      end
      else if (flags and QSF_SUBMETA)<>0 then
      begin
        lplvcd^.clrTextBk:=cbkg_sub;
        lplvcd^.clrText  :=cfgr_sub;
      end
      else if (flags and QSF_INLIST)=0 then
      begin
        lplvcd^.clrTextBk:=cbkg_hid; 
        lplvcd^.clrText  :=cfgr_hid;
      end
      else
        idx:=-1;
    end;
  end
  else
    idx:=-1;
  if idx<0 then
  begin
    if (not qsopt.drawgrid) and odd(lplvcd^.nmcd.dwItemSpec) then
    begin
      lplvcd^.clrTextBk:=cbkg_odd; 
      lplvcd^.clrText  :=cfgr_odd; 
    end
    else
    begin
      lplvcd^.clrTextBk:=cbkg_norm;
      lplvcd^.clrText  :=cfgr_norm;
    end;
  end;
end;

function ProcessCustomDraw(lParam:LPARAM):integer;
var
  lplvcd:PNMLVCUSTOMDRAW;
  rc:TRECT;
  h:HICON;
  buf:array [0..255] of AnsiChar;
  i,j,sub:integer;
begin
  lplvcd:=pointer(lParam);
  result:=CDRF_DODEFAULT;
  case lplvcd^.nmcd.dwDrawStage of
    CDDS_PREPAINT: begin
      result:=CDRF_NOTIFYITEMDRAW;
      exit;
    end;
    CDDS_ITEMPREPAINT: begin
      result:=CDRF_NOTIFYSUBITEMDRAW;

      SetCellColor(lplvcd,LV_GetLParam(grid,lplvcd^.nmcd.dwItemSpec));
      
      exit;
    end;
    CDDS_SUBITEM or CDDS_ITEMPREPAINT: begin

      i:=LV_GetLParam(grid,lplvcd^.nmcd.dwItemSpec);
      SetCellColor(lplvcd,i);
      sub:=GetQSColumn(lplvcd^.iSubItem);
      if (qsopt.columns[sub].flags and COL_GENDER)<>0 then
      begin
        ListView_GetSubItemRect(grid,lplvcd^.nmcd.dwItemSpec,lplvcd^.iSubItem,LVIR_ICON,@rc);

        case MainBuf[i,sub].data of
          70: h:=hIconF;
          77: h:=hIconM;
        else
          h:=0;
        end;
        if h<>0 then
        begin
          DrawIconEx(lplvcd^.nmcd.hdc,rc.left+1,rc.top,h,16,16,0,0,DI_NORMAL);
        end;
        result:=CDRF_SKIPDEFAULT;
      end
      else if (qsopt.columns[sub].flags and COL_XSTATUS)<>0 then
      begin
        if IsAnsi then
          j:=StrToInt(pAnsiChar(MainBuf[i,sub].text))
        else
          j:=StrToInt(MainBuf[i,sub].text);
        if j>0 then
        begin
          StrCopy(buf,FlagBuf[i].proto);
          StrCat(buf,PS_ICQ_GETCUSTOMSTATUSICON);
          if PluginLink^.ServiceExists(buf)<>0 then
          begin
            h:=CallService(buf,j,LR_SHARED);

            ListView_GetSubItemRect(grid,lplvcd^.nmcd.dwItemSpec,lplvcd^.iSubItem,LVIR_ICON,@rc);
            DrawIconEx(lplvcd^.nmcd.hdc,rc.left+1,rc.top,h,16,16,0,0,DI_NORMAL);
          end;
        end;
        result:=CDRF_SKIPDEFAULT;
      end
      else if qsopt.showclienticons and
           ((qsopt.columns[sub].flags and COL_CLIENT)<>0) then
        result:=CDRF_NOTIFYPOSTPAINT;
    end;
    CDDS_SUBITEM or CDDS_ITEMPOSTPAINT: begin
      sub:=GetQSColumn(lplvcd^.iSubItem);
      if (qsopt.columns[sub].flags and COL_CLIENT)<>0 then
      begin
        i:=LV_GetLParam(grid,lplvcd^.nmcd.dwItemSpec);
        if IsAnsi then
          StrCopy(buf,PAnsiChar(MainBuf[i,sub].text))
        else
          FastWideToAnsiBuf(MainBuf[i,sub].text,buf);
        
//        ListView_GetItemTextA(grid,lplvcd^.nmcd.dwItemSpec,lplvcd^.iSubItem,buf,SizeOf(buf));
        if buf[0]<>#0 then
        begin
          h:=PluginLink^.CallService(MS_FP_GETCLIENTICON,dword(@buf),1);
          ListView_GetSubItemRect(grid,lplvcd^.nmcd.dwItemSpec,lplvcd^.iSubItem,LVIR_ICON,@rc);
          DrawIconEx(lplvcd^.nmcd.hdc,rc.left+1,rc.top,h,16,16,0,0,DI_NORMAL);
          DestroyIcon(h);
        end;
        result:=CDRF_SKIPDEFAULT;
      end;
    end;
  end;
end;

function NewEditProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):integer; stdcall;
var
  count,current,next,perpage:integer;
  li:LV_ITEM;
begin
  result:=0;
  case hMessage of 
    WM_CHAR: if wParam=27 then
    begin
      PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDCANCEL,0);
      exit;
    end;
    WM_KEYUP: if wParam=VK_RETURN then
    begin
      if ListView_GetSelectedCount(grid)=1 then
        ShowContactMsgDlg(GetFocusedhContact);
      exit;
    end;
    WM_KEYDOWN: begin
      count  :=ListView_GetItemCount(grid);
      current:=ListView_GetNextItem(grid,-1,LVNI_FOCUSED);
      next:=-1;
      if count>0 then
        case wParam of
          VK_NEXT,VK_PRIOR: begin
            perpage:=ListView_GetCountPerPage(grid);
            if wParam=VK_NEXT then
              next:=min(current+perpage,count)
            else
              next:=max(current-perpage,0);
          end;
          VK_UP: begin
            if current>0 then
              next:=current-1
          end;
          VK_DOWN: begin
            if current<count-1 then
            next:=current+1
          end;
          VK_F5: begin
            PostMessage(GetParent(Dialog),WM_COMMAND,(BN_CLICKED shl 16)+IDC_REFRESH,0);
            exit;
          end;
        end;
      if next>=0 then
      begin
        li.statemask:=LVIS_SELECTED;
        li.state:=0;
        SendMessage(grid,LVM_SETITEMSTATE,-1,integer(@li));
        ListView_SetItemState(grid,next,LVIS_FOCUSED or LVIS_SELECTED,
            LVIS_FOCUSED or LVIS_SELECTED);
  //      ListView_EnsureVisible(grid,next,false);
        SendMessage(grid,LVM_ENSUREVISIBLE,next,0);
        result:=0;
        exit;
      end;
    end;
  end;
  result:=CallWindowProc(OldEditProc,dialog,hMessage,wParam,lParam);
end;

function ShowContactMenu(wnd:HWND;hContact:THANDLE):HMENU;
var
  pt:tpoint;
begin
  if hContact<>0 then
  begin
    GetCursorPos(pt);
    result:=PluginLink^.CallService(MS_CLIST_MENUBUILDCONTACT,hContact,0);
    if result<>0 then
    begin
      TrackPopupMenu(result,0,pt.x,pt.y,0,wnd,nil);
      DestroyMenu(result);
    end;
  end
  else
    result:=0;
end;

procedure ShowMultiPopup(cnt:integer);
var
  mmenu,grpmenu:HMENU;
  i:integer;
  buf:array [0..255] of WideChar;
  p:PWideChar;
  pt:TPOINT;
  b:array [0..31] of AnsiChar;
  pc:pAnsiChar;
  sl:PWStrList;
  sla:PStrList;
begin
  mmenu:=CreatePopupMenu;
  if mmenu=0 then
    exit;

  if IsAnsi then
  begin
    StrCopy(pAnsiChar(@buf),Translate('Selected'));
    pc:=@buf;
    while pc^<>#0 do inc(pc);
    pc^:=' '; inc(pc);

    IntToStr(pc,cnt);

    while pc^<>#0 do inc(pc);
    pc^:=' '; inc(pc);
    StrCopy(pc,Translate('contacts'));
    AppendMenuA(mmenu,MF_DISABLED+MF_STRING,0,pAnsiChar(@buf));
    AppendMenuA(mmenu,MF_SEPARATOR,0,nil);
    AppendMenuA(mmenu,MF_STRING,101,Translate('&Delete'));
    AppendMenuA(mmenu,MF_STRING,102,Translate('&Copy'));
    if PluginLink^.ServiceExists(MS_MC_CONVERTTOMETA)<>0 then
      AppendMenuA(mmenu,MF_STRING,103,Translate('C&onvert to Meta'));

    grpmenu:=CreatePopupMenu;
    i:=0;
    AppendMenuA(grpmenu,MF_STRING,1234,Translate('<Root Group>'));
    AppendMenuA(grpmenu,MF_SEPARATOR,0,nil);
    sla:=NewStrList;
    repeat
      pc:=DBReadString(0,'CListGroups',IntToStr(b,i),nil);
      if pc=nil then break;
      sla.Add(pc+1);
      mFreeMem(pc);
      inc(i);
    until false;
    sla.Sort(false);
    for i:=0 to sla.Count-1 do
    begin
      AppendMenuA(grpmenu,MF_STRING,i+1,pAnsiChar(sla.Items[i]));
    end;
    sla.Clear;
    sla.Free;

    AppendMenuA(mmenu,MF_POPUP,grpmenu,Translate('&Move to Group'));
  end
  else
  begin
    StrCopyW(buf,TranslateW('Selected'));
    p:=@buf;
    while p^<>#0 do inc(p);
    p^:=' '; inc(p);

    IntToStr(p,cnt);

    while p^<>#0 do inc(p);
    p^:=' '; inc(p);
    StrCopyW(p,TranslateW('contacts'));
    AppendMenuW(mmenu,MF_DISABLED+MF_STRING,0,buf);
    AppendMenuW(mmenu,MF_SEPARATOR,0,nil);
    AppendMenuW(mmenu,MF_STRING,101,TranslateW('&Delete'));
    AppendMenuW(mmenu,MF_STRING,102,TranslateW('&Copy'));
    if PluginLink^.ServiceExists(MS_MC_CONVERTTOMETA)<>0 then
      AppendMenuW(mmenu,MF_STRING,103,TranslateW('C&onvert to Meta'));

    grpmenu:=CreatePopupMenu;
    i:=0;
    AppendMenuW(grpmenu,MF_STRING,1234,TranslateW('<Root Group>'));
    AppendMenuW(grpmenu,MF_SEPARATOR,0,nil);
    sl:=NewWStrList;
    repeat
      p:=DBReadUnicode(0,'CListGroups',IntToStr(b,i),nil);
      if p=nil then break;
      sl.Add(p+1);
      mFreeMem(p);
      inc(i);
    until false;
    sl.Sort(false);
    for i:=0 to sl.Count-1 do
    begin
      AppendMenuW(grpmenu,MF_STRING,i+1,pWideChar(sl.Items[i]));
    end;
    sl.Clear;
    sl.Free;

//    grpmenu:=CallService(MS_CLIST_GROUPBUILDMENU,0,0);
    AppendMenuW(mmenu,MF_POPUP,grpmenu,TranslateW('&Move to Group'));
  end;
  GetCursorPos(pt);
  i:=integer(TrackPopupMenu(mmenu,TPM_RETURNCMD+TPM_NONOTIFY,pt.x,pt.y,0,mainwnd,nil));
  case i of
    101: DeleteByList;
    102: begin
      if IsAnsi then
        CopyMultiLinesA(ListView_GetSelectedCount(grid))
      else
        CopyMultiLinesW(ListView_GetSelectedCount(grid))
    end;
    103: ConvertToMeta;
  else
    if i>0 then
    begin // move to group
      if i=1234 then // root group
        buf[0]:=#0
      else
      begin
        if IsAnsi then
          GetMenuStringA(grpmenu,i,pAnsiChar(@buf),SizeOf(buf),MF_BYCOMMAND)
        else
          GetMenuStringW(grpmenu,i,buf,SizeOf(buf),MF_BYCOMMAND);
      end;
      MoveToGroup(buf);
    end;
  end;
  DestroyMenu(mmenu);
  if qsopt.closeafteraction then
    CloseSrWindow;
end;

procedure addcolumn(handle:hwnd;num,width:integer;title:PAnsiChar); overload;
var
  lvcol:LV_COLUMNA;
begin
  zeromemory(@lvcol,sizeof(lvcol));
  lvcol.mask      :=LVCF_TEXT or LVCF_WIDTH;
  lvcol.pszText   :=title;
  lvcol.cx        :=width;
  SendMessageA(handle,LVM_INSERTCOLUMNA,num,integer(@lvcol));
end;

procedure addcolumn(handle:hwnd;num,width:integer;title:PWideChar); overload;
var
  lvcol:LV_COLUMNW;
begin
  zeromemory(@lvcol,sizeof(lvcol));
  lvcol.mask      :=LVCF_TEXT or LVCF_WIDTH;
  lvcol.pszText   :=title;
  lvcol.cx        :=width;
  SendMessageW(handle,LVM_INSERTCOLUMNW,num,integer(@lvcol));
end;

// from zero!!
function GetNthByMask(const arr:tcolumnarray; num:cardinal; mask:dword):tcolumnitem;
var
  i:cardinal;
begin
  for i:=0 to HIGH(arr) do
  begin
    if (arr[i].flags and mask)<>0 then
    begin
      if num=0 then
      begin
        result:=arr[i];
        exit;
      end;
      dec(num);
    end;
  end;
  result:=arr[0];
end;
{
function QSKbdHook(code:integer;wParam:integer;lParam:longint):longint; stdcall;
begin
  if (code=HC_ACTION) and
     (lParam>0) and (LoWord(lParam)=1) then
  begin
  end;
  result:=CallNextHookEx(KbHook,code,wParam,lParam);
end;
}

function ColorReload(wParam:WPARAM;lParam:LPARAM):int;cdecl;
begin
  result:=0;
  cbkg_norm:=GetColor(bkg_norm);
  cfgr_norm:=GetColor(fgr_norm);
  cbkg_odd :=GetColor(bkg_odd);
  cfgr_odd :=GetColor(fgr_odd);
  cbkg_dis :=GetColor(bkg_dis);
  cfgr_dis :=GetColor(fgr_dis);
  cbkg_del :=GetColor(bkg_del);
  cfgr_del :=GetColor(fgr_del);
  cbkg_hid :=GetColor(bkg_hid);
  cfgr_hid :=GetColor(fgr_hid);
  cbkg_meta:=GetColor(bkg_meta);
  cfgr_meta:=GetColor(fgr_meta);
  cbkg_sub :=GetColor(bkg_sub);
  cfgr_sub :=GetColor(fgr_sub);
end;

procedure ClearBuffers;
var
  w,h:integer;
begin
  for w:=0 to HIGH(FlagBuf) do
    mFreeMem(FlagBuf[w].proto);
  for w:=0 to HIGH(MainBuf) do
    for h:=0 to HIGH(MainBuf[0]) do
      mFreeMem(MainBuf[w,h].text);
end;

procedure SetSpecialColumns(num:integer);
begin
  with qsopt.columns[num] do
  begin
    if (setting_type=ST_BYTE) and
       (lstrcmpia(wparam.a,'XStatusId')=0) then
    begin
      flags:=flags or COL_XSTATUS;
    end

    else if (setting_type=ST_CONTACTINFO) and
            (setting_cnftype=CNF_GENDER) then
    begin
      if hIconF=0 then hIconF:=PluginLink^.CallService(MS_SKIN2_GETICON,0,dword(QS_FEMALE));
      if hIconM=0 then hIconM:=PluginLink^.CallService(MS_SKIN2_GETICON,0,dword(QS_MALE));
      flags:=flags or COL_GENDER;
      if IsAnsi then
      begin
        tstrMale   :=pWideChar(Translate('Male'));
        tstrFemale :=pWideChar(Translate('Female'));
        tstrUnknown:=pWideChar(Translate('Unknown'));
      end
      else
      begin
        tstrMale   :=TranslateW('Male');
        tstrFemale :=TranslateW('Female');
        tstrUnknown:=TranslateW('Unknown');
      end;
    end

    else if (wparam.a<>NIL) and // FingerPrint preprocess
       (setting_type=ST_STRING) and
       (lstrcmpia(wparam.a,'MirVer')=0) and
       (PluginLink^.ServiceExists(MS_FP_GETCLIENTICON)<>0) then
      flags:=flags or COL_CLIENT;
  end;
end;

function FindAddDlgResizer(Dialog:HWND;lParam:LPARAM;urc:PUTILRESIZECONTROL):int; cdecl;
begin
  case urc^.wId of
    IDC_E_SEARCHTEXT:   result:=RD_ANCHORX_WIDTH or RD_ANCHORY_TOP;
    IDCANCEL:           result:=RD_ANCHORX_RIGHT or RD_ANCHORY_TOP;
    IDC_REFRESH:        result:=RD_ANCHORX_RIGHT or RD_ANCHORY_TOP;
    IDC_CH_SHOWOFFLINE: result:=RD_ANCHORX_LEFT  or RD_ANCHORY_TOP;
    IDC_CH_COLORIZE:    result:=RD_ANCHORX_LEFT  or RD_ANCHORY_TOP;
    IDC_LIST:           result:=RD_ANCHORX_WIDTH or RD_ANCHORY_HEIGHT;
    IDC_STATUSBAR:      result:=RD_ANCHORX_WIDTH or RD_ANCHORY_BOTTOM;
  else
    result:=0;
  end;
end;

procedure PrepareTable(reset:boolean=false);
var
  i:integer;
  old:integer;
begin
  old:=tablecolumns;
  tablecolumns:=0;
  for i:=0 to qsopt.numcolumns-1 do
  begin
    with qsopt.columns[i] do
    begin
      if (flags and COL_ON)<>0 then
      begin
        if IsAnsi then
          addcolumn(grid,tablecolumns,width,Translate(pAnsiChar(title)))
        else
          addcolumn(grid,tablecolumns,width,TranslateW(title));
        inc(tablecolumns);
      end;

      SetSpecialColumns(i);
    end;
  end;
  if reset then
  begin
    for i:=old+tablecolumns-1 downto tablecolumns do
    begin
      SendMessage(grid,LVM_DELETECOLUMN,i,0);
    end;
  end;

  ListView_DeleteAllItems(grid);
  ListView_SetItemCount(grid,HIGH(FlagBuf)+1);
end;

function QSMainWndProc(Dialog:HWnd;hMessage:UINT;wParam:WPARAM;lParam:LPARAM):integer; stdcall;
var
  tmp:cardinal;
  w,h:cardinal;
  i:integer;
  buf:array [0..255] of WideChar;
  rc:TRECT;
  pt:TPOINT;
  smenu:HMENU;
  TI:tToolInfoW;
  urd:TUTILRESIZEDIALOG;
begin
  result:=0;
  case hMessage of
    WM_DESTROY: begin
      PluginLink^.UnhookEvent(colorhook);

      StatusBar:=0;
      DeleteObject(gridbrush);
      GetWindowRect(dialog,rc);

      CopyRect(qsopt.grrect,rc);

      // set column width - only for enabled columns
      for tmp:=0 to qsopt.numcolumns-1 do
      begin
        if {(qsopt.columns[tmp].flags and COL_ON)<>0} colorder[tmp]>=0 then
        begin
          w:=ListView_GetColumnWidth(grid,colorder[tmp]);
          if w<>0 then
            qsopt.columns[tmp].width:=w;
        end;
      end;
      saveopt_wnd;

      ListView_SetImageList(grid,0,LVSIL_SMALL);
      opened:=false;

      tmp:=GetDC(grid);
      h:=GetCurrentObject(tmp,OBJ_FONT);
      SendMessage(grid,WM_SETFONT,0,1);
      DeleteObject(h);
      ReleaseDC(grid,tmp);

      grid:=0;

      if qsopt.savepattern then
        if IsAnsi then
          DBWriteString (0,qs_module,'pattern',pAnsiChar(pattern))
        else
          DBWriteUnicode(0,qs_module,'pattern',pattern);

      mFreeMem(patstr);
      mFreeMem(pattern);

      ClearBuffers;
    end;

    WM_INITDIALOG: begin

      tmp:=GetModuleHandle(nil);
      if sortcoldn=0 then
        sortcoldn:=LoadImage(tmp,PAnsiChar(240),IMAGE_BITMAP,0,0,LR_LOADMAP3DCOLORS);
      if sortcolup=0 then
        sortcolup:=LoadImage(tmp,PAnsiChar(239),IMAGE_BITMAP,0,0,LR_LOADMAP3DCOLORS);

      if IsAnsi then
        SetWindowTextA(dialog,'Quick Search')
      else
        SetWindowTextW(dialog,'Quick Search');

      StatusBar:=GetDlgItem(Dialog,IDC_STATUSBAR);

      smenu:=GetSystemMenu(dialog,false);
      InsertMenu (smenu,5,MF_BYPOSITION or MF_SEPARATOR,0,nil);
      if IsAnsi then
        InsertMenuA(smenu,6,MF_BYPOSITION or MF_STRING,
          IDM_STAYONTOP,Translate('Stay on Top'))
      else
        InsertMenuW(smenu,6,MF_BYPOSITION or MF_STRING,
          IDM_STAYONTOP,TranslateW('Stay on Top'));

      if qsopt.stayontop then
      begin
        CheckMenuItem(smenu,IDM_STAYONTOP,MF_BYCOMMAND or MF_CHECKED);
        SetWindowPos(dialog,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE);
      end;
      if qsopt.showoffline then
        CheckDlgButton(dialog,IDC_CH_SHOWOFFLINE,ORD(qsopt.showoffline));

      if qsopt.colorize then
        CheckDlgButton(dialog,IDC_CH_COLORIZE,ORD(qsopt.colorize));

      gridbrush:=CreateSolidBrush(RGB(222,230,235));

      mainwnd:=dialog;
      if IsAnsi then
      begin
        tmp:=GetWindowLongA(Dialog,GWL_EXSTYLE);
        if qsopt.usetoolstyle then
          tmp:=tmp or WS_EX_TOOLWINDOW
        else
          tmp:=tmp and not WS_EX_TOOLWINDOW;
        SetWindowLongPtrA(dialog,GWL_EXSTYLE,tmp);
      end
      else
      begin
        tmp:=GetWindowLongW(Dialog,GWL_EXSTYLE);
        if qsopt.usetoolstyle then
          tmp:=tmp or WS_EX_TOOLWINDOW
        else
          tmp:=tmp and not WS_EX_TOOLWINDOW;
        SetWindowLongPtrW(dialog,GWL_EXSTYLE,tmp);
      end;

      SendMessage(dialog,WM_SETICON,ICON_SMALL,//LoadIcon(hInstance,PAnsiChar(IDI_QS))
        PluginLink^.CallService(MS_SKIN2_GETICON,0,dword(QS_QS)));
      grid:=GetDlgItem(dialog,IDC_LIST);

      ListView_SetImageList(grid,
         PluginLink^.CallService(MS_CLIST_GETICONSIMAGELIST,0,0),LVSIL_SMALL);

      tmp:=LVS_EX_FULLROWSELECT or LVS_EX_SUBITEMIMAGES or LVS_EX_HEADERDRAGDROP or LVS_EX_LABELTIP;
      if qsopt.drawgrid then
        tmp:=tmp or LVS_EX_GRIDLINES;
      SendMessage(grid,LVM_SETEXTENDEDLISTVIEWSTYLE,0,tmp);

      if IsAnsi then
      begin
        OldLVProc  :=pointer(SetWindowLongPtrA(grid,GWL_WNDPROC,integer(@NewLVProc)));
        OldEditProc:=pointer(SetWindowLongPtrA(GetDlgItem(dialog,IDC_E_SEARCHTEXT),
           GWL_WNDPROC,integer(@NewEditProc)));

        oldproc:=pointer(SetWindowLongPtrA(
            SendMessage(grid,LVM_GETHEADER,0,0),
            GWL_WNDPROC,integer(@NewLVHProc)));

      end
      else
      begin
        OldLVProc  :=pointer(SetWindowLongPtrW(grid,GWL_WNDPROC,integer(@NewLVProc)));
        OldEditProc:=pointer(SetWindowLongPtrW(GetDlgItem(dialog,IDC_E_SEARCHTEXT),
           GWL_WNDPROC,integer(@NewEditProc)));

        oldproc:=pointer(SetWindowLongPtrW(
            SendMessage(grid,LVM_GETHEADER,0,0),
            GWL_WNDPROC,integer(@NewLVHProc)));

      end;

      PrepareTable;
      
      if pattern<>nil then
      begin
        if IsAnsi then
          SetDlgItemTextA(Dialog,IDC_E_SEARCHTEXT,pAnsiChar(pattern))
        else
          SetDlgItemTextW(Dialog,IDC_E_SEARCHTEXT,pattern)
      end
      else
        FillGrid;

      TranslateDialogDefault(dialog);

      SnapToScreen(qsopt.grrect);
      with qsopt.grrect do
        MoveWindow(dialog,left,top,right-left,bottom-top,false);

      with TI do
      begin
        cbSize     :=SizeOf(TI);
        uFlags     :=TTF_SUBCLASS+TTF_IDISHWND;
        hWnd       :=Dialog;
        uId        :=grid;
        hInst      :=0;
        lpszText   :=nil;
      end;
      if IsAnsi then
      begin
        HintWnd:=CreateWindowExA(0,TOOLTIPS_CLASS,nil,0,
            integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
            integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
            Dialog,0,HInstance,NIL);

        SendMessageA(HintWnd,TTM_ADDTOOLA,0,DWORD(@TI));
      end
      else
      begin
        HintWnd:=CreateWindowExW(0,TOOLTIPS_CLASS,nil,0,
            integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
            integer(CW_USEDEFAULT),integer(CW_USEDEFAULT),
            Dialog,0,HInstance,NIL);

        SendMessageW(HintWnd,TTM_ADDTOOLW,0,DWORD(@TI));
      end;
//      SetWindowsHookEx(WH_KEYBOARD,@QSKbdHook,0,GetCurrentThreadId);
      colorhook:=PluginLink^.HookEvent(ME_COLOUR_RELOAD,@ColorReload);
      
      opened:=true;
    end;

    WM_GETMINMAXINFO: begin
      with PMINMAXINFO(lParam)^ do
      begin
        ptMinTrackSize.x:=300;
        ptMinTrackSize.y:=160;
      end;
    end;

    WM_SIZE: begin
      SendMessage(StatusBar,WM_SIZE,0,0);
      FillChar(urd,SizeOf(TUTILRESIZEDIALOG),0);
      urd.cbSize    :=SizeOf(urd);
      urd.hwndDlg   :=Dialog;
      urd.hInstance :=hInstance;
      urd.lpTemplate:=MAKEINTRESOURCEA(IDD_MAIN);
      urd.lParam    :=0;
      urd.pfnResizer:=@FindAddDlgResizer;
      CallService(MS_UTILS_RESIZEDIALOG,0,dword(@urd));
    end;

    WM_SYSCOMMAND: begin
      if wParam=IDM_STAYONTOP then
      begin
        if qsopt.stayontop then
        begin
          h:=MF_BYCOMMAND or MF_UNCHECKED;
          w:=HWND_NOTOPMOST;
        end
        else
        begin
          h:=MF_BYCOMMAND or MF_CHECKED;
          w:=HWND_TOPMOST;
        end;
        CheckMenuItem(GetSystemMenu(dialog,false),IDM_STAYONTOP,h);
        SetWindowPos(dialog,w,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE);
        qsopt.stayontop:=not qsopt.stayontop;
        exit;
      end;
    end;

    WM_CONTEXTMENU: begin
      if wParam=tWPARAM(GetDlgItem(dialog,IDC_LIST)) then
      begin
        w:=ListView_GetSelectedCount(grid);
        if w>1 then
          ShowMultiPopup(w)
        else
          ShowContactMenu(Dialog,GetFocusedhContact);
      end;
    end;

    WM_MYADDCONTACT: begin
      // refresh table to add contact
      i:=Length(MainBuf);
      SetLength(MainBuf,i+1);
      SetLength(MainBuf[i],qsopt.numcolumns);
      SetLength(FlagBuf,i+1);

      AddContact(i,wParam);
      ProcessLine(i);
      Sort;
      UpdateSB;
    end;

    WM_MYDELETECONTACT: begin
      i:=FindBufNumber(wParam);
      if i>=0 then
      begin
        FlagBuf[i].flags:=(FlagBuf[i].flags or QSF_DELETED) and not QSF_ACTIVE;
        for w:=0 to HIGH(MainBuf[0]) do
          mFreeMem(MainBuf[i,w].text);
        i:=FindItem(i);
        if i>=0 then
          ListView_DeleteItem(grid,i);
        UpdateSB;
      end;
    end;

    WM_MEASUREITEM:
      PluginLink^.CallService(MS_CLIST_MENUMEASUREITEM,wParam,lParam);
    WM_DRAWITEM:
      PluginLink^.CallService(MS_CLIST_MENUDRAWITEM,wParam,lParam);

    WM_MOUSEMOVE: begin
      if TTInstalled then
      begin
        GetWindowRect(grid,rc);
        pt.x:=loword(lParam);
        pt.y:=hiword(lParam);
        ClientToScreen(Dialog,pt);
        if not PtInRect(rc,pt) then
        begin
          if TTShowed then
          begin
            TTShowed:=false;
            CallService(MS_TIPPER_HIDETIP,0,0);
          end;
          KillTimer(grid,TIMERID_HOVER);
        end;
      end;
    end;

    WM_KEYDOWN: begin
      case wParam of
        VK_F5: begin
          PostMessage(Dialog,WM_COMMAND,(BN_CLICKED shl 16)+IDC_REFRESH,0);
          exit;
        end;
      end;
    end;

    WM_COMMAND: begin
      if opened and (PluginLink^.CallService(MS_CLIST_MENUPROCESSCOMMAND,
          MAKEWPARAM(LOWORD(wParam),MPCF_CONTACTMENU),
          GetFocusedhContact)<>0) then
      begin
        if qsopt.closeafteraction then
          CloseSrWindow;
        exit;
      end;

      case wParam shr 16 of
        EN_CHANGE: begin
          if IsAnsi then
          begin
            GetDlgItemTextA(Dialog,IDC_E_SEARCHTEXT,pAnsiChar(@buf),sizeOf(buf));
            mFreeMem(pattern);
            StrDup(pAnsiChar(pattern),pAnsiChar(@buf));
            if pattern<>nil then
              CharLowerA(pAnsiChar(pattern));
          end
          else
          begin
            GetDlgItemTextW(Dialog,IDC_E_SEARCHTEXT,buf,sizeOf(buf));
            mFreeMem(pattern);
            StrDupW(pattern,buf);
            if pattern<>nil then
              CharLowerW(pattern);
          end;
          FillGrid; //!!
        end;

        BN_CLICKED: begin
          case loword(wParam) of
            IDC_CH_SHOWOFFLINE: begin
              qsopt.showoffline:=IsDlgButtonChecked(dialog,IDC_CH_SHOWOFFLINE)<>BST_UNCHECKED;
              ShowHideOffline(qsopt.showoffline);
            end;

            IDC_CH_COLORIZE: begin
              qsopt.colorize:=IsDlgButtonChecked(dialog,IDC_CH_COLORIZE)<>BST_UNCHECKED;
              RedrawWindow(grid,nil,0,RDW_INVALIDATE);
            end;

            IDC_REFRESH: begin
              ClearBuffers;
              PrepareToFill;
              PrepareTable(true);
              FillGrid;
            end;

            IDCANCEL: CloseSRWindow();
          end;
        end;
      end;
    end;

    WM_NOTIFY: begin
      case integer(PNMHdr(lParam)^.code) of
        LVN_COLUMNCLICK: begin
          ColumnClick(PNMListView(lParam)^.hdr.hwndFrom,PNMListView(lParam)^.iSubItem);
        end;
        NM_CUSTOMDRAW: begin
          if PNMHdr(lParam)^.hwndFrom=grid then
          begin
            if IsAnsi then
              SetWindowLongPtrA(dialog,DWL_MSGRESULT,ProcessCustomDraw(lParam))
            else
              SetWindowLongPtrW(dialog,DWL_MSGRESULT,ProcessCustomDraw(lParam));
            result:=1;
          end;
        end;
      end;
    end;

//  else
//    result:=DefWindowProc(Dialog,hMessage,wParam,lParam);
  end;
end;

function CloseSrWindow:boolean;
begin
  result:=true;
  if opened and (mainwnd<>0) then
  begin
    DestroyWindow(mainwnd);
    opened:=false;
    mainwnd:=0;
  end;
end;

function OpenSRWindow(apattern:PWideChar;flags:integer):boolean;
begin
  result:=true;
  if opened then
    exit;
  
  TTInstalled := PluginLink^.ServiceExists(MS_TIPPER_SHOWTIP)<>0;
  // too lazy to move pattern and flags to thread
  if IsAnsi then
  begin
    if apattern<>nil then
    begin
      if flags<>0 then
        StrDup(pAnsiChar(pattern),pAnsiChar(apattern))
      else
        WideToAnsi(PWideChar(apattern),pAnsiChar(pattern));
      CharLowerA(pAnsiChar(pattern));
    end
    else if qsopt.savepattern then
      pattern:=pWideChar(DBReadString(0,qs_module,'pattern',nil))
    else
      pattern:=nil;
  end
  else
  begin
    if apattern<>nil then
    begin
      if flags=0 then
        StrDupW(pattern,apattern)
      else
        AnsiToWide(PAnsiChar(apattern),pattern);
      CharLowerW(pattern);
    end
    else if qsopt.savepattern then
      pattern:=DBReadUnicode(0,qs_module,'pattern',nil)
    else
      pattern:=nil;
  end;

  if PrepareToFill then
  begin
//!!    SetLength(colorder,qsopt.numcolumns);
    ColorReload(0,0);

    if IsAnsi then
      CreateDialogA(hInstance,PAnsiChar(IDD_MAIN),0,@QSMainWndProc)
    else
      CreateDialogW(hInstance,PWideChar(IDD_MAIN),0,@QSMainWndProc);
  end;
end;

function BringToFront:integer;
var
  wp:TWINDOWPLACEMENT;
begin
  result:=1;
  wp.length:=SizeOf(TWINDOWPLACEMENT);
  GetWindowPlacement(mainwnd,@wp);
  if wp.showCmd=SW_SHOWMINIMIZED then
    ShowWindow(mainwnd,SW_RESTORE);
  SetForegroundWindow(mainwnd);
end;

procedure ChangeStatusPicture(row:integer; hContact:dword;Pic:integer);
var
  li:LV_ITEM;
begin
  row:=FindItem(row);
  if row>=0 then
  begin
    li.iItem   :=row;
    li.iSubItem:=0;
    li.mask    :=LVIF_IMAGE;
    li.iImage  :=pic;//PluginLink^.CallService(MS_CLIST_GETCONTACTICON,hContact,0);
    SendMessage(grid,LVM_SETITEM,0,integer(@li));
  end;
end;

function OnStatusChanged(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
var
  j:integer;
  oldstat,newstat:integer;
begin
  result:=0;
  if not opened then exit;

  j:=FindBufNumber(wParam);
  if j>=0 then
  begin
    oldstat:=FlagBuf[j].status;
    newstat:=DBReadWord(wParam,FlagBuf[j].proto,'Status',ID_STATUS_OFFLINE);
    FlagBuf[j].status:=newstat;

    if (oldstat<>ID_STATUS_OFFLINE) and (newstat<>ID_STATUS_OFFLINE) then
      ChangeStatusPicture(j,wParam,lParam)
    else if (oldstat=ID_STATUS_OFFLINE) {and (newstat<>ID_STATUS_OFFLINE)} then
    begin
      if qsopt.showoffline then
        ChangeStatusPicture(j,wParam,lParam)
      else
        ProcessLine(j,false)
    end
    else if {(oldstat<>ID_STATUS_OFFLINE) and} (newstat=ID_STATUS_OFFLINE) then
    begin
      if qsopt.showoffline then
        ChangeStatusPicture(j,wParam,lParam)
      else
      begin
        FlagBuf[j].flags:=FlagBuf[j].flags and not QSF_ACTIVE;
        ListView_DeleteItem(grid,FindItem(j));
      end;
    end;

  // refresh table to new filtering
    if qsopt.sortbystatus then
      Sort;
    UpdateSB;
  end;
end;

function OnContactAdded(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
begin
  result:=0;
  if opened then
    PostMessage(mainwnd,WM_MYADDCONTACT,wParam,lParam);
end;

function OnContactDeleted(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
begin
  result:=0;
  if opened then
    PostMessage(mainwnd,WM_MYDELETECONTACT,wParam,lParam);
end;

function OnAccountChanged(wParam:WPARAM;lParam:LPARAM):integer;cdecl;
begin
  result:=0;
  if not opened then exit;
  case wParam of
    PRAC_ADDED: begin
    end;
    PRAC_REMOVED: begin
    end;
    PRAC_CHECKED: begin
      with PPROTOACCOUNT(lParam)^ do
      begin
        if bIsEnabled<>0 then
        begin
        end
        else
        begin
        end;
      end;
    end;
  end;
end;

function ShiftIndex(idx:integer;var order:array of integer):pointer;
var
  i,n:integer;
begin
  n:=colorder[idx];
  for i:=0 to qsopt.numcolumns-1 do
    if order[i]>n then dec(order[i]);
  result:=@order;
end;

procedure FillLVColumn(column,lvcolumn:integer);
var
  li:LV_ITEMW;
  i:integer;
begin
  FillChar(li,SizeOf(li),0);
  for i:=0 to ListView_GetItemCount(grid)-1 do
  begin
    li.iItem   :=i;
    li.mask    :=LVIF_PARAM;
    li.iSubItem:=0;
    SendMessage(grid,LVM_GETITEM,0,dword(@li));

    li.pszText :=MainBuf[li.lParam,column].text;
    // Client icons preprocess
    if (((qsopt.columns[column].flags and COL_CLIENT)<>0) and
       (li.pszText<>NIL) and qsopt.showclienticons) OR
       ((qsopt.columns[column].flags and (COL_XSTATUS or COL_GENDER))<>0) then
      li.mask:=LVIF_IMAGE or LVIF_TEXT
    else
      li.mask:=LVIF_TEXT;
    li.iSubItem:=lvcolumn;
    if IsAnsi then
      SendMessageA(grid,LVM_SETITEMA,0,integer(@li))
    else
      SendMessageW(grid,LVM_SETITEMW,0,integer(@li));
  end;
end;

procedure SetColumnOrder;
var
  i,col:integer;
  lcol:array [0..99] of integer;
begin
  col:=0;
  for i:=0 to qsopt.numcolumns-1 do
    if colorder[i]>=0 then
    begin
      lcol[col]:=colorder[i];
      inc(col);
    end;

  SendMessageW(grid,LVM_SETCOLUMNORDERARRAY,col,dword(@lcol[0]));

  InvalidateRect(grid,nil,false);
end;

procedure WndChangeColumns(code:integer;column:integer=-1);
var
  i,col:integer;
  coldata:QSRec;
//  lcol:array of integer;
  incr:integer;
begin
  if (grid<>0) and
     ((code=wcRefresh) or ((column>=0) and (column<qsopt.numcolumns))) then
  begin
    SendMessage(grid,WM_SETREDRAW,0,0);
    case code of
      wcUp,wcDown: begin
        // changing buffer data
        if code=wcUp then
          incr:=-1
        else
          incr:=1;

        // memory
        for i:=0 to HIGH(MainBuf) do
        begin
          coldata               :=MainBuf[i,column];
          MainBuf[i,column     ]:=MainBuf[i,column+incr];
          MainBuf[i,column+incr]:=coldata;
        end;

        // index
        col                  :=colorder[column];
        colorder[column     ]:=colorder[column+incr];
        colorder[column+incr]:=col;

        // check needs for screen resort (columns are AFTER resort)
        if ((qsopt.columns[column     ].flags and COL_ON)=COL_ON) and
           ((qsopt.columns[column+incr].flags and COL_ON)=COL_ON) then // both visible
        begin // need resort on screen
          SetColumnOrder;
        end;
        SendMessage(grid,WM_SETREDRAW,1,0);
        exit;
      end;

      wcHide: begin // hide column
        // screen
        SendMessage(grid,LVM_DELETECOLUMN,colorder[column],0);
        dec(tablecolumns);
        // index
        ShiftIndex(column,colorder);
        colorder[column]:=-1;
      end;

      wcDelete: begin // delete column
        // screen
        SendMessage(grid,LVM_DELETECOLUMN,colorder[column],0);
        dec(tablecolumns);
        // memory
        for i:=0 to HIGH(MainBuf) do
        begin
          mFreeMem(MainBuf[i,column].text);
          if column<qsopt.numcolumns then
            move(MainBuf[i,column+1],MainBuf[i,column],SizeOf(QSRec));
        end;
        SetLength(MainBuf,Length(MainBuf),qsopt.numcolumns); //!!!!
        // index
        if column<qsopt.numcolumns then
          move(colorder[column+1],colorder[column],SizeOf(integer));
        SetLength(colorder,qsopt.numcolumns);
      end;

      wcShow: begin // show column
        // memory
        if (qsopt.columns[column].flags and COL_INIT)=0 then
        begin
          for i:=0 to HIGH(MainBuf) do // contacts
          begin
            LoadOneItem(FlagBuf[i].contact,column,FlagBuf[i].proto,MainBuf[i,column]);
          end;
          qsopt.columns[column].flags:=qsopt.columns[column].flags or COL_INIT;
        end;
        // screen
        with qsopt.columns[column] do // atm - to the end only
          if IsAnsi then
            addcolumn(grid,tablecolumns,width,Translate(pAnsiChar(title)))
          else
            addcolumn(grid,tablecolumns,width,TranslateW(title));
        
        // fill new column
        FillLVColumn(column,tablecolumns);
        // index
        colorder[column]:=tablecolumns;
        inc(tablecolumns);

        SetColumnOrder;
{
        SetLength(lcol,tablecolumns);
        col:=0;
        for i:=0 to qsopt.numcolumns-1 do
          if colorder[i]>=0 then
          begin
            lcol[col]:=colorder[i];
            inc(col);
          end;

        SendMessageW(grid,LVM_SETCOLUMNORDERARRAY,tablecolumns,dword(@lcol[0]));

        InvalidateRect(grid,nil,false);
}
      end;

      wcInsert: begin // add column
        // memory
        SetLength(MainBuf,Length(MainBuf),qsopt.numcolumns+1); //!!!!
        SetSpecialColumns(column);
        // index
        SetLength(colorder,qsopt.numcolumns+1);
        // screen
        if (qsopt.columns[column].flags and COL_ON)<>0 then
          WndChangeColumns(wcShow,column)
        else
          colorder[column]:=-1;
      end;

      wcChange: begin // change column
        for i:=0 to HIGH(MainBuf) do
        begin
          mFreeMem(MainBuf[i,column].text);
        end;
        SetSpecialColumns(column);
        qsopt.columns[column].flags:=qsopt.columns[column].flags and not COL_INIT;
        if (qsopt.columns[column].flags and COL_ON)<>0 then
          FillLVColumn(column,colorder[column]);
      end;

      wcRefresh: begin // refresh all info
        ClearBuffers;
        PrepareToFill;
        PrepareTable(true);
      end;
    end;
    FillGrid;
    SendMessage(grid,WM_SETREDRAW,1,0);
  end;
end;

begin
end.
