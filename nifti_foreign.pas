unit nifti_foreign;

interface
{$H+}
{$DEFINE GZIP}
{$DEFINE GUI}
{$DEFINE GL10} //define for MRIcroGL1.0, comment fro MRIcroGL1.2 and later
{$H+}
{$IFDEF GL10}
{$Include isgui.inc}
{$ENDIF}
uses

{$IFDEF GL10} define_types,
        {$IFNDEF FPC}gziod,{$ELSE}gzio2,{$ENDIF}
{$ENDIF}
{$IFDEF GZIP}zstream, {$ENDIF}
{$IFDEF GUI}
 dialogs,
{$ELSE}
 dialogsx,
{$ENDIF}
//ClipBrd,
 nifti_types,  sysutils, classes, StrUtils;//2015! dialogsx

{$IFDEF GL10}
procedure NII_Clear (out lHdr: TNIFTIHdr);
procedure NII_SetIdentityMatrix (var lHdr: TNIFTIHdr); //create neutral rotation matrix
{$ELSE}
Type
    	ByteRA = array [1..1] of byte;
	Bytep = ^ByteRA;
procedure UnGZip(const FileName: string; buffer: bytep; offset, sz: integer);
{$ENDIF}
function readForeignHeader (var lFilename: string; var lHdr: TNIFTIhdr; var gzBytes: int64; var swapEndian, isDimPermute2341: boolean): boolean;
procedure convertForeignToNifti(var nhdr: TNIFTIhdr);
function FSize (lFName: String): Int64;
function isTIFF(fnm: string): boolean;
implementation

//uses mainunit;
const
    kNaNSingle : single = 1/0;
Type

  mat44 = array [0..3, 0..3] of Single;
  vect4 = array [0..3] of Single;
  mat33 = array [0..2, 0..2] of Single;
  vect3 = array [0..2] of Single;
  ivect3 = array [0..2] of integer;

{$IFDEF GL10}
procedure NII_SetIdentityMatrix (var lHdr: TNIFTIHdr); //create neutral rotation matrix
var lInc: integer;
begin
	with lHdr do begin
		 for lInc := 0 to 3 do
			 srow_x[lInc] := 0;
		 for lInc := 0 to 3 do
             srow_y[lInc] := 0;
         for lInc := 0 to 3 do
             srow_z[lInc] := 0;
         for lInc := 1 to 16 do
             intent_name[lInc] := chr(0);
         //next: create identity matrix: if code is switched on there will not be a problem
		 srow_x[0] := 1;
         srow_y[1] := 1;
         srow_z[2] := 1;
    end;
end; //proc NIFTIhdr_IdentityMatrix

procedure NII_Clear (out lHdr: TNIFTIHdr);
var
 lInc: integer;
begin
  with lHdr do begin
    HdrSz := sizeof(TNIFTIhdr);
    for lInc := 1 to 10 do
       Data_Type[lInc] := chr(0);
    for lInc := 1 to 18 do
       db_name[lInc] := chr(0);
    extents:=0;
    session_error:= 0;
    regular:='r'{chr(0)};
    dim_info:=(0);
    dim[0] := 4;
    for lInc := 1 to 7 do
       dim[lInc] := 0;
    intent_p1 := 0;
    intent_p2 := 0;
    intent_p3 := 0;
    intent_code:=0;
    datatype:=0 ;
    bitpix:=0;
    slice_start:=0;
    for lInc := 1 to 7 do
       pixdim[linc]:= 1.0;
    vox_offset:= 0.0;
    scl_slope := 1.0;
    scl_inter:= 0.0;
    slice_end:= 0;
    slice_code := 0;
    xyzt_units := 10;
    cal_max:= 0.0;
    cal_min:= 0.0;
    slice_duration:=0;
    toffset:= 0;
    glmax:= 0;
    glmin:= 0;
    for lInc := 1 to 80 do
      descrip[lInc] := chr(0);{80 spaces}
    for lInc := 1 to 24 do
      aux_file[lInc] := chr(0);{80 spaces}
    {below are standard settings which are not 0}
    bitpix := 16;//vc16; {8bits per pixel, e.g. unsigned char 136}
    DataType := 4;//vc4;{2=unsigned char, 4=16bit int 136}
    Dim[0] := 3;
    Dim[1] := 256;
    Dim[2] := 256;
    Dim[3] := 1;
    Dim[4] := 1; {n vols}
    Dim[5] := 1;
    Dim[6] := 1;
    Dim[7] := 1;
    glMin := 0;
    glMax := 255;
    qform_code := kNIFTI_XFORM_UNKNOWN;
    sform_code:= kNIFTI_XFORM_UNKNOWN;
    quatern_b := 0;
    quatern_c := 0;
    quatern_d := 0;
    qoffset_x := 0;
    qoffset_y := 0;
    qoffset_z := 0;
    NII_SetIdentityMatrix(lHdr);
    magic := kNIFTI_MAGIC_SEPARATE_HDR;
  end; //with the NIfTI header...
end;
{$ENDIF}

function UpCaseExt(lFileName: string): string;
var lI: integer;
l2ndExt,lExt : string;
begin
         lExt := ExtractFileExt(lFileName);
         if length(lExt) > 0 then
        	for lI := 1 to length(lExt) do
        		lExt[lI] := upcase(lExt[lI]);
         result := lExt;
         if lExt <> '.GZ' then exit;
         lI := length(lFileName) - 6;
         if li < 1 then exit;
         l2ndExt := upcase(lFileName[lI])+upcase(lFileName[lI+1])+upcase(lFileName[li+2])+upcase(lFileName[li+3]);
         if (l2ndExt = '.NII')then
        	result :=  l2ndExt+lExt
         else if  (l2ndExt = 'BRIK') and (lI > 1) and (lFileName[lI-1] = '.') then
              result := '.BRIK'+lExt;
end;

{$IFNDEF GL10}
procedure UnGZip(const FileName: string; buffer: bytep; offset, sz: integer);
{$IFDEF GZIP}
var
   decomp: TGZFileStream;
   skip: array of byte;
begin
     decomp := TGZFileStream.create(FileName, gzopenread);
     if offset > 0 then begin
        setlength(skip, offset);
        decomp.Read(skip[0], offset);
     end;
     decomp.Read(buffer[0], sz);
     decomp.free;
end;
{$ELSE}
begin
  {$IFDEF UNIX} writeln('Recompile with GZ support!'); {$ENDIF}
end;
{$ENDIF}
{$ENDIF}
(*  function isECAT(fnm: string): boolean;
  type
  THdrMain = packed record //Next: ECAT signature
    magic: array[1..14] of char;
  end;
  var
    f: file;
    mhdr: THdrMain;
  begin
    result := false;
    if not fileexists(fnm) then exit;
    if DirectoryExists(fnm) then exit;
    if FSize(fnm) < 32 then exit;
    {$I-}
    AssignFile(f, fnm);
    FileMode := fmOpenRead;  //Set file access to read only
    Reset(f, 1);
    {$I+}
    if ioresult <> 0 then
       exit;
    BlockRead(f, mhdr, sizeof(mhdr));
    closefile(f);
    if ((mhdr.magic[1] <> 'M') or (mhdr.magic[2] <> 'A') or (mhdr.magic[3] <> 'T') or (mhdr.magic[4] <> 'R') or (mhdr.magic[5] <> 'I') or (mhdr.magic[6] <> 'X')) then
       exit;
    result := true;
  end; *)
  function FSize (lFName: String): Int64;
var SearchRec: TSearchRec;
begin
  result := 0;
  if not fileexists(lFName) then exit;
  FindFirst(lFName, faAnyFile, SearchRec);
  result := SearchRec.size;
  FindClose(SearchRec);
end;

  function Swap2(s : SmallInt): smallint;
  type
    swaptype = packed record
      case byte of
        0:(Word1 : word); //word is 16 bit
        1:(Small1: SmallInt);
    end;
    swaptypep = ^swaptype;
  var
    inguy:swaptypep;
    outguy:swaptype;
  begin
    inguy := @s; //assign address of s to inguy
    outguy.Word1 := swap(inguy^.Word1);
    result :=outguy.Small1;
  end;

procedure Xswap4r ( var s:single);
type
  swaptype = packed record
	case byte of
	  0:(Word1,Word2 : word); //word is 16 bit
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word2);
  outguy.Word2 := swap(inguy^.Word1);
  inguy^.Word1 := outguy.Word1;
  inguy^.Word2 := outguy.Word2;
end;

procedure swap4(var s : LongInt);
type
  swaptype = packed record
    case byte of
      0:(Word1,Word2 : word); //word is 16 bit
      1:(Long:LongInt);
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word2);
  outguy.Word2 := swap(inguy^.Word1);
  s:=outguy.Long;
end;


procedure pswap4r ( var s:single);
type
  swaptype = packed record
    case byte of
      0:(Word1,Word2 : word); //word is 16 bit
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word2);
  outguy.Word2 := swap(inguy^.Word1);
  inguy^.Word1 := outguy.Word1;
  inguy^.Word2 := outguy.Word2;
end; //proc Xswap4r

procedure pswap4i(var s : LongInt);
type
  swaptype = packed record
    case byte of
      0:(Word1,Word2 : word); //word is 16 bit
      1:(Long:LongInt);
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word2);
  outguy.Word2 := swap(inguy^.Word1);
  s:=outguy.Long;
end; //proc swap4

function swap64r(s : double):double;
type
  swaptype = packed record
    case byte of
      0:(Word1,Word2,Word3,Word4 : word); //word is 16 bit
      1:(float:double);
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word4);
  outguy.Word2 := swap(inguy^.Word3);
  outguy.Word3 := swap(inguy^.Word2);
  outguy.Word4 := swap(inguy^.Word1);
  try
    swap64r:=outguy.float;
  except
        swap64r := 0;
        exit;
  end;{}
end;

FUNCTION specialsingle (var s:single): boolean;
//returns true if s is Infinity, NAN or Indeterminate
//4byte IEEE: msb[31] = signbit, bits[23-30] exponent, bits[0..22] mantissa
//exponent of all 1s =   Infinity, NAN or Indeterminate
CONST kSpecialExponent = 255 shl 23;
VAR Overlay: LongInt ABSOLUTE s;
BEGIN
  IF ((Overlay AND kSpecialExponent) = kSpecialExponent) THEN
     RESULT := true
  ELSE
      RESULT := false;
END;

function isBioFormats(fnm: string): string;
//detect LIF and LIFF format or other Imagej/Fiji Bioformat
const
     LIF_MAGIC_BYTE = $70;
     LIF_MEMORY_BYTE = $2a;
var
  f: file;
  bs: array[0..255] of byte;
begin
  result := '';
  if not fileexists(fnm) then exit;
  if DirectoryExists(fnm) then exit;
  if FSize(fnm) < 256 then exit;
  {$I-}
  AssignFile(f, fnm);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(f, 1);
  {$I+}
  if ioresult <> 0 then
     exit;
  BlockRead(f, bs, sizeof(bs)); //Byte-order Identifier
  if (bs[8] = LIF_MEMORY_BYTE) and ((bs[0] = LIF_MAGIC_BYTE) or (bs[3] = LIF_MAGIC_BYTE)) then
     result := 'LIF'; //file can be read using LIFReader.java
  if (bs[4] = ord('i')) and (bs[5] = ord('m')) and (bs[6] = ord('p')) and (bs[7] = ord('r')) then
     result := 'LIFF'; //Openlab LIFF format OpenLabReader.java
  if (bs[0] = $D0) and (bs[1] = $CF) and (bs[2] = $11) and (bs[3] = $E0) then //IPW_MAGIC_BYTES = 0xd0cf11e0
     result := 'IPW'; //IPWReader.java
  if (bs[0] = ord('i')) and (bs[1] = ord('i')) and (bs[2] = ord('i')) and (bs[3] = ord('i')) then
     result := 'IPL';//IPLabReader.java
  if (bs[0] = $89) and (bs[1] = $48) and (bs[2] = $44) and (bs[3] = $46) then //IPW_MAGIC_BYTES = 0xd0cf11e0
     result := 'HDF';//Various readers: ImarisHDFReader, CellH5Reader, etc
  if (bs[0] = $DA) and (bs[1] = $CE) and (bs[2] = $BE) and (bs[3] = $0A) then//DA CE BE 0A
     result := 'ND2';//MAGIC_BYTES_1 ND2Reader
  if (bs[0] = $6a) and (bs[1] = $50) and (bs[2] = $20) and (bs[3] = $20) then
     result := 'ND2';//MAGIC_BYTES_2 ND2Reader
  if (bs[208] = $4D) and (bs[209] = $41) and (bs[210] = $50) then
     result := 'MAP';//MRCReader http://www.ccpem.ac.uk/mrc_format/mrc2014.php
  //GatanReader.java
  closefile(f);
end;

  function isTIFF(fnm: string): boolean;
  var
    f: file;
    w: word;
  begin
    result := false;
    if not fileexists(fnm) then exit;
    if DirectoryExists(fnm) then exit;
    if FSize(fnm) < 32 then exit;
    {$I-}
    AssignFile(f, fnm);
    FileMode := fmOpenRead;  //Set file access to read only
    Reset(f, 1);
    {$I+}
    if ioresult <> 0 then
       exit;
    w := 0;
    BlockRead(f, w, sizeof(w)); //Byte-order Identifier
    if (w = $4D4D) or (w = $4949) then
       result := true;
    closefile(f);
  end;

{$IFDEF GUI}
procedure ShowMsg(s: string);
begin
     Showmessage(s);
end;
{$ENDIF}

procedure fromMatrix (m: mat44; var r11,r12,r13,r21,r22,r23,r31,r32,r33: double);
begin
  r11 := m[0,0];
  r12 := m[0,1];
  r13 := m[0,2];
  r21 := m[1,0];
  r22 := m[1,1];
  r23 := m[1,2];
  r31 := m[2,0];
  r32 := m[2,1];
  r33 := m[2,2];
end;

function Matrix2D (r11,r12,r13,r21,r22,r23,r31,r32,r33: double): mat33;
begin
  result[0,0] := r11;
  result[0,1] := r12;
  result[0,2] := r13;
  result[1,0] := r21;
  result[1,1] := r22;
  result[1,2] := r23;
  result[2,0] := r31;
  result[2,1] := r32;
  result[2,2] := r33;
end;

function nifti_mat33_determ( R: mat33 ):double;   //* determinant of 3x3 matrix */
begin
  result := r[0,0]*r[1,1]*r[2,2]
           -r[0,0]*r[2,1]*r[1,2]
           -r[1,0]*r[0,1]*r[2,2]
           +r[1,0]*r[2,1]*r[0,2]
           +r[2,0]*r[0,1]*r[1,2]
           -r[2,0]*r[1,1]*r[0,2] ;
end;

function nifti_mat33_rownorm( A: mat33 ): single;  // max row norm of 3x3 matrix
var
   r1,r2,r3: single ;
begin
   r1 := abs(A[0,0])+abs(A[0,1])+abs(A[0,2]);
   r2 := abs(A[1,0])+abs(A[1,1])+abs(A[1,2]);
   r3 := abs(A[2,0])+abs(A[2,1])+abs(A[2,2]);
   if( r1 < r2 ) then r1 := r2 ;
   if( r1 < r3 ) then r1 := r3 ;
   result := r1 ;
end;

procedure fromMatrix33 (m: mat33; var r11,r12,r13,r21,r22,r23,r31,r32,r33: double);
begin
  r11 := m[0,0];
  r12 := m[0,1];
  r13 := m[0,2];
  r21 := m[1,0];
  r22 := m[1,1];
  r23 := m[1,2];
  r31 := m[2,0];
  r32 := m[2,1];
  r33 := m[2,2];
end;


function nifti_mat33_inverse( R: mat33 ): mat33;   //* inverse of 3x3 matrix */
var
   r11,r12,r13,r21,r22,r23,r31,r32,r33 , deti: double ;
begin
   FromMatrix33(R,r11,r12,r13,r21,r22,r23,r31,r32,r33);
   deti := r11*r22*r33-r11*r32*r23-r21*r12*r33
         +r21*r32*r13+r31*r12*r23-r31*r22*r13 ;
   if( deti <> 0.0 ) then deti := 1.0 / deti ;
   result[0,0] := deti*( r22*r33-r32*r23) ;
   result[0,1] := deti*(-r12*r33+r32*r13) ;
   result[0,2] := deti*( r12*r23-r22*r13) ;
   result[1,0] := deti*(-r21*r33+r31*r23) ;
   result[1,1] := deti*( r11*r33-r31*r13) ;
   result[1,2] := deti*(-r11*r23+r21*r13) ;
   result[2,0] := deti*( r21*r32-r31*r22) ;
   result[2,1] := deti*(-r11*r32+r31*r12) ;
   result[2,2] := deti*( r11*r22-r21*r12) ;
end;

function nifti_mat33_colnorm( A: mat33 ): single;  //* max column norm of 3x3 matrix */
var
   r1,r2,r3: single ;
begin
   r1 := abs(A[0,0])+abs(A[1,0])+abs(A[2,0]) ;
   r2 := abs(A[0,1])+abs(A[1,1])+abs(A[2,1]) ;
   r3 := abs(A[0,2])+abs(A[1,2])+abs(A[2,2]) ;
   if( r1 < r2 ) then r1 := r2 ;
   if( r1 < r3 ) then r1 := r3 ;
   result := r1 ;
end;

function nifti_mat33_polar( A: mat33 ): mat33;
var
   k:integer;
   X , Y , Z: mat33 ;
   dif,alp,bet,gam,gmi : single;
begin
  dif := 1;
  k := 0;
   X := A ;
   gam := nifti_mat33_determ(X) ;
   while( gam = 0.0 )do begin        //perturb matrix
     gam := 0.00001 * ( 0.001 + nifti_mat33_rownorm(X) ) ;
     X[0,0] := X[0,0]+gam ;
     X[1,1] := X[1,1]+gam ;
     X[2,2] := X[2,2] +gam ;
     gam := nifti_mat33_determ(X) ;
   end;
   while true do begin
     Y := nifti_mat33_inverse(X) ;
     if( dif > 0.3 )then begin     // far from convergence
       alp := sqrt( nifti_mat33_rownorm(X) * nifti_mat33_colnorm(X) ) ;
       bet := sqrt( nifti_mat33_rownorm(Y) * nifti_mat33_colnorm(Y) ) ;
       gam := sqrt( bet / alp ) ;
       gmi := 1.0 / gam ;
     end else begin
       gam := 1.0;
       gmi := 1.0 ;  //close to convergence
     end;
     Z[0,0] := 0.5 * ( gam*X[0,0] + gmi*Y[0,0] ) ;
     Z[0,1] := 0.5 * ( gam*X[0,1] + gmi*Y[1,0] ) ;
     Z[0,2] := 0.5 * ( gam*X[0,2] + gmi*Y[2,0] ) ;
     Z[1,0] := 0.5 * ( gam*X[1,0] + gmi*Y[0,1] ) ;
     Z[1,1] := 0.5 * ( gam*X[1,1] + gmi*Y[1,1] ) ;
     Z[1,2] := 0.5 * ( gam*X[1,2] + gmi*Y[2,1] ) ;
     Z[2,0] := 0.5 * ( gam*X[2,0] + gmi*Y[0,2] ) ;
     Z[2,1] := 0.5 * ( gam*X[2,1] + gmi*Y[1,2] ) ;
     Z[2,2] := 0.5 * ( gam*X[2,2] + gmi*Y[2,2] ) ;
     dif := abs(Z[0,0]-X[0,0])+abs(Z[0,1]-X[0,1])+abs(Z[0,2]-X[0,2])
           +abs(Z[1,0]-X[1,0])+abs(Z[1,1]-X[1,1])+abs(Z[1,2]-X[1,2])
           +abs(Z[2,0]-X[2,0])+abs(Z[2,1]-X[2,1])+abs(Z[2,2]-X[2,2]);
     k := k+1 ;
     if( k > 100) or (dif < 3.e-6 ) then begin
         result := Z;
         break ; //convergence or exhaustion
     end;
     X := Z ;
   end;
   result := Z ;
end;

procedure nifti_mat44_to_quatern( lR :mat44;
                             var qb, qc, qd,
                             qx, qy, qz,
                             dx, dy, dz, qfac : single);
var
   r11,r12,r13 , r21,r22,r23 , r31,r32,r33, xd,yd,zd , a,b,c,d : double;
   P,Q: mat33;  //3x3
begin
   // offset outputs are read write out of input matrix
   qx := lR[0,3];
   qy := lR[1,3];
   qz := lR[2,3];
   //load 3x3 matrix into local variables
   fromMatrix(lR,r11,r12,r13,r21,r22,r23,r31,r32,r33);
   //compute lengths of each column; these determine grid spacings
   xd := sqrt( r11*r11 + r21*r21 + r31*r31 ) ;
   yd := sqrt( r12*r12 + r22*r22 + r32*r32 ) ;
   zd := sqrt( r13*r13 + r23*r23 + r33*r33 ) ;
   //if a column length is zero, patch the trouble
   if( xd = 0.0 )then begin r11 := 1.0 ; r21 := 0; r31 := 0.0 ; xd := 1.0 ; end;
   if( yd = 0.0 )then begin r22 := 1.0 ; r12 := 0; r32 := 0.0 ; yd := 1.0 ; end;
   if( zd = 0.0 )then begin r33 := 1.0 ; r13 := 0; r23 := 0.0 ; zd := 1.0 ; end;
   //assign the output lengths
   dx := xd;
   dy := yd;
   dz := zd;
   //normalize the columns
   r11 := r11/xd ; r21 := r21/xd ; r31 := r31/xd ;
   r12 := r12/yd ; r22 := r22/yd ; r32 := r32/yd ;
   r13 := r13/zd ; r23 := r23/zd ; r33 := r33/zd ;
   { At this point, the matrix has normal columns, but we have to allow
      for the fact that the hideous user may not have given us a matrix
      with orthogonal columns. So, now find the orthogonal matrix closest
      to the current matrix.
      One reason for using the polar decomposition to get this
      orthogonal matrix, rather than just directly orthogonalizing
      the columns, is so that inputting the inverse matrix to R
      will result in the inverse orthogonal matrix at this point.
      If we just orthogonalized the columns, this wouldn't necessarily hold.}
   Q :=  Matrix2D (r11,r12,r13,          // 2D "graphics" matrix
                           r21,r22,r23,
                           r31,r32,r33);
   P := nifti_mat33_polar(Q) ; //P is orthog matrix closest to Q
   FromMatrix33(P,r11,r12,r13,r21,r22,r23,r31,r32,r33);
{                           [ r11 r12 r13 ]
 at this point, the matrix  [ r21 r22 r23 ] is orthogonal
                            [ r31 r32 r33 ]
 compute the determinant to determine if it is proper}

   zd := r11*r22*r33-r11*r32*r23-r21*r12*r33
       +r21*r32*r13+r31*r12*r23-r31*r22*r13 ; //should be -1 or 1

   if( zd > 0 )then begin // proper
     qfac  := 1.0 ;
   end else begin //improper ==> flip 3rd column
     qfac := -1.0 ;
     r13 := -r13 ; r23 := -r23 ; r33 := -r33 ;
   end;
   // now, compute quaternion parameters
   a := r11 + r22 + r33 + 1.0;
   if( a > 0.5 ) then begin  //simplest case
     a := 0.5 * sqrt(a) ;
     b := 0.25 * (r32-r23) / a ;
     c := 0.25 * (r13-r31) / a ;
     d := 0.25 * (r21-r12) / a ;
   end else begin  //trickier case
     xd := 1.0 + r11 - (r22+r33) ;// 4*b*b
     yd := 1.0 + r22 - (r11+r33) ;// 4*c*c
     zd := 1.0 + r33 - (r11+r22) ;// 4*d*d
     if( xd > 1.0 ) then begin
       b := 0.5 * sqrt(xd) ;
       c := 0.25* (r12+r21) / b ;
       d := 0.25* (r13+r31) / b ;
       a := 0.25* (r32-r23) / b ;
     end else if( yd > 1.0 ) then begin
       c := 0.5 * sqrt(yd) ;
       b := 0.25* (r12+r21) / c ;
       d := 0.25* (r23+r32) / c ;
       a := 0.25* (r13-r31) / c ;
     end else begin
       d := 0.5 * sqrt(zd) ;
       b := 0.25* (r13+r31) / d ;
       c := 0.25* (r23+r32) / d ;
       a := 0.25* (r21-r12) / d ;
     end;
     if( a < 0.0 )then begin b:=-b ; c:=-c ; d:=-d; {a:=-a; this is not used} end;
   end;
   qb := b ;
   qc := c ;
   qd := d ;
end;

procedure ZERO_MAT44(var m: mat44); //note sets m[3,3] to one
var
  i,j: integer;
begin
  for i := 0 to 3 do
    for j := 0 to 3 do
      m[i,j] := 0.0;
  m[3,3] := 1;
end;

procedure LOAD_MAT33(out m: mat33; m00,m01,m02, m10,m11,m12, m20,m21,m22: single);
begin
  m[0,0] := m00;
  m[0,1] := m01;
  m[0,2] := m02;
  m[1,0] := m10;
  m[1,1] := m11;
  m[1,2] := m12;
  m[2,0] := m20;
  m[2,1] := m21;
  m[2,2] := m22;
end;

function nifti_mat33vec_mul(m: mat33; v: vect3): vect3;
var
  i: integer;
begin
     for i := 0 to 2 do
         result[i] := (v[0]*m[i,0])+(v[1]*m[i,1])+(v[2]*m[i,2]);
end;

function nifti_mat33_mul( A,B: mat33): mat33;
var
  i,j: integer;
begin
     for i:=0 to 2 do
    	for j:=0 to 2 do
            result[i,j] :=  A[i,0] * B[0,j]
            + A[i,1] * B[1,j]
            + A[i,2] * B[2,j] ;
end;

procedure LOAD_MAT44(var m: mat44; m00,m01,m02,m03, m10,m11,m12,m13, m20,m21,m22,m23: single);
begin
  m[0,0] := m00;
  m[0,1] := m01;
  m[0,2] := m02;
  m[0,3] := m03;
  m[1,0] := m10;
  m[1,1] := m11;
  m[1,2] := m12;
  m[1,3] := m13;
  m[2,0] := m20;
  m[2,1] := m21;
  m[2,2] := m22;
  m[2,3] := m23;
  m[3,0] := 0.0;
  m[3,1] := 0.0;
  m[3,2] := 0.0;
  m[3,3] := 1.0;
end;

function validMatrix(var m: mat44): boolean;
var
  i: integer;
begin
     result := false;
     for i := 0 to 2 do begin
         if (m[0,i] = 0.0) and (m[1,i] = 0.0) and (m[2,i] = 0.0) then exit;
         if (m[i,0] = 0.0) and (m[i,1] = 0.0) and (m[i,2] = 0.0) then exit;
     end;
     result := true;
end;

procedure convertForeignToNifti(var nhdr: TNIFTIhdr);
var
  i,nonSpatialMult: integer;
  qto_xyz: mat44;
   //dumqx, dumqy, dumqz,
     dumdx, dumdy, dumdz: single;
begin
  nhdr.HdrSz := 348; //used to signify header does not need to be byte-swapped
	nhdr.magic:=kNIFTI_MAGIC_EMBEDDED_HDR;
	if (nhdr.dim[3] = 0) then nhdr.dim[3] := 1; //for 2D images the 3rd dim is not specified and set to zero
	nhdr.dim[0] := 3; //for 2D images the 3rd dim is not specified and set to zero
  nonSpatialMult := 1;
  for i := 4 to 7 do
    if nhdr.dim[i] > 0 then
      nonSpatialMult := nonSpatialMult * nhdr.dim[i];
	if (nonSpatialMult > 1) then begin
    nhdr.dim[0] := 4;
    nhdr.dim[4] := nonSpatialMult;
    for i := 5 to 7 do
      nhdr.dim[i] := 0;
  end;
  nhdr.bitpix := 8;
  if (nhdr.datatype = 4) or (nhdr.datatype = 512) then nhdr.bitpix := 16;
  if (nhdr.datatype = 8) or (nhdr.datatype = 16) or (nhdr.datatype = 768) then nhdr.bitpix := 32;
  if (nhdr.datatype = 32) or (nhdr.datatype = 64) or (nhdr.datatype = 1024) or (nhdr.datatype = 1280) then nhdr.bitpix := 64;
  LOAD_MAT44(qto_xyz, nhdr.srow_x[0], nhdr.srow_x[1], nhdr.srow_x[2], nhdr.srow_x[3],
              nhdr.srow_y[0], nhdr.srow_y[1], nhdr.srow_y[2], nhdr.srow_y[3],
              nhdr.srow_z[0], nhdr.srow_z[1], nhdr.srow_z[2], nhdr.srow_z[3]);
  if not validMatrix(qto_xyz) then begin
     nhdr.sform_code := 0;
     nhdr.qform_code :=  0;
     for i := 0 to 3 do begin
         nhdr.srow_x[i] := 0;
         nhdr.srow_y[i] := 0;
         nhdr.srow_z[i] := 0;
     end;
     nhdr.srow_x[0] := 1;
     nhdr.srow_y[1] := 1;
     nhdr.srow_z[2] := 1;
     exit;
  end;
  nhdr.sform_code := 1;
  nifti_mat44_to_quatern( qto_xyz , nhdr.quatern_b, nhdr.quatern_c, nhdr.quatern_d,nhdr.qoffset_x,nhdr.qoffset_y,nhdr.qoffset_z, dumdx, dumdy, dumdz,nhdr.pixdim[0]) ;
  nhdr.qform_code := 0;//kNIFTI_XFORM_SCANNER_ANAT;
end;

procedure NSLog( str: string);
begin
  {$IFDEF GUI}
  showmsg(str);
  {$ENDIF}
  {$IFDEF UNIX}writeln(str);{$ENDIF}
end;

function parsePicString(s: string): single;
//given "AXIS_4 001 0.000000e+00 4.000000e-01 microns"  return 0.4
var
  sList : TStringList;
begin
  result := 0.0;
  DecimalSeparator := '.';
  sList := TStringList.Create;
  sList.Delimiter := ' ';        // Each list item will be blank separated
  sList.DelimitedText := s;
  if sList.Count > 4 then begin
     //ShowMessage(sList[3]);
     try
        result := StrToFloat(sList[3]);    // Middle blanks are not supported
     except
           //ShowMessage(Exception.Message);
     end;
  end;
  sList.Free;
end;

function nii_readVmr (var fname: string; isV16: boolean; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//http://support.brainvoyager.com/automation-aamp-development/23-file-formats/385-developer-guide-26-the-format-of-vmr-files.html
Type
  Tvmr_header = packed record //Next: VMR Format Header structure
        ver, nx, ny, nz: word; //  0,4,8,12
  end; // Tbv_header;
  (*Tvmr_tail = packed record //
  	Xoff,Yoff,Zoff,FramingCube: int16; //v3
	PosFlag,CoordSystem: int32;
	X1, Y1, Z1,Xn,Yn,Zn, RXv,RYv,RZv, CXv,CYv,CZv: single;
	nRmat, nCmat: int32;
	Rfov, Cfov, Zthick, Zgap: single;
	nTrans: int32;
	LRconv: uint8;
	vXres, vYres, vZres: single;
	isResVerified, isTal: uint8;
	min, mean, max: int32;
  end; *)
var
   vhdr : Tvmr_header;
   //vtail : Tvmr_tail;
   lHdrFile: file;
   xSz, nvox, FSz, Hsz : integer;
begin
  result := false;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading vmr header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  FSz := Filesize(lHdrFile);
  BlockRead(lHdrFile, vhdr, sizeof(Tvmr_header));
  nVox := vhdr.nx * vhdr.ny * vhdr.nz;
  if isV16 then
    xSz := (2 * nVox) + sizeof(Tvmr_header)
  else
    xSz := nVox + sizeof(Tvmr_header);//+ sizeof(Tvmr_tail);
  Hsz := sizeof(Tvmr_header);
  if (xSz > FSz) then begin //version 1? (6 byte header)
     nVox := vhdr.ver * vhdr.nx * vhdr.ny;
     if isV16 then
        xSz := (2 * nVox) + 6
     else
         xSz := nVox + 6;
     if (xSz = FSz) then begin //version 1
        vhdr.nz := vhdr.ny;
        vhdr.ny := vhdr.nx;
        vhdr.nx := vhdr.ver;
        vhdr.ver := 1;
        Hsz := 6;
     end;
  end;
  if (xSz > FSz) then begin //docs do not specify endian - wrong endian?
     showmessage(format('Odd v16 or vmr format image %dx%dx%d ver %d sz %d', [vhdr.nx, vhdr.ny, vhdr.nz, vhdr.ver, FSz] ));
     CloseFile(lHdrFile);
     exit;
  end;
  //seek(lHdrFile, nVox + sizeof(Tvmr_header));
  //BlockRead(lHdrFile, vtail, sizeof(Tvmr_tail));
  CloseFile(lHdrFile);
  swapEndian := false;
  nhdr.dim[0]:=3;//3D
  nhdr.dim[1]:=vhdr.nx;
  nhdr.dim[2]:=vhdr.ny;
  nhdr.dim[3]:=vhdr.nz;
  nhdr.dim[4]:=1;
  nhdr.pixdim[1]:=1.0;
  nhdr.pixdim[2]:=1.0;
  nhdr.pixdim[3]:=1.0;
  //Need examples
  //if vtail.isResVerified > 0 then begin
  //  showmessage(format('%g %g %g',[vtail.X1, vtail.Y1, vtail.Z1]));
  //end;
  nhdr.bitpix:= 8;
  nhdr.datatype := kDT_UNSIGNED_CHAR;
  if isV16 then begin
     nhdr.bitpix:= 16;
     nhdr.datatype := kDT_INT16;
  end;
  nhdr.vox_offset := HSz;
  nhdr.sform_code := 1;
  nhdr.srow_x[0]:=nhdr.pixdim[1];nhdr.srow_x[1]:=0.0;nhdr.srow_x[2]:=0.0;nhdr.srow_x[3]:=0.0;
  nhdr.srow_y[0]:=0.0;nhdr.srow_y[1]:=nhdr.pixdim[2];nhdr.srow_y[2]:=0.0;nhdr.srow_y[3]:=0.0;
  nhdr.srow_z[0]:=0.0;nhdr.srow_z[1]:=0.0;nhdr.srow_z[2]:=-nhdr.pixdim[3];nhdr.srow_z[3]:=0.0;
  convertForeignToNifti(nhdr);
  //nhdr.scl_inter:= 1;
  //nhdr.scl_slope := -1;
  result := true;
end; //nii_readVmr()

function nii_readBVox (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//http://pythology.blogspot.com/2014/08/you-can-do-cool-stuff-with-manual.html
Type
  Tbv_header = packed record //Next: PIC Format Header structure
        nx, ny, nz, nvol : LongInt; //  0,4,8,12
  end; // Tbv_header;
var
   bhdr : Tbv_header;
   lHdrFile: file;
   nvox, nvoxswap, FSz : integer;
begin
  result := false;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading BVox header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  FSz := Filesize(lHdrFile);
  BlockRead(lHdrFile, bhdr, sizeof(Tbv_header));
  CloseFile(lHdrFile);
  swapEndian := false;
  nVox := bhdr.nx * bhdr.ny * bhdr.nz * bhdr.nvol * 4; //*4 as 32-bpp
  if (nVox + sizeof(Tbv_header) ) <> FSz then begin
    swapEndian := true;
    pswap4i(bhdr.nx);
    pswap4i(bhdr.ny);
    pswap4i(bhdr.nz);
    pswap4i(bhdr.nvol);
    nVoxSwap := bhdr.nx * bhdr.ny * bhdr.nz * bhdr.nvol * 4; //*4 as 32-bpp
    if (nVoxSwap + sizeof(Tbv_header) ) <> FSz then begin
       NSLog('Not a valid BVox file: expected filesize of '+inttostr(nVoxSwap)+' or '+inttostr(nVox)+' bytes');
       exit;
    end;

  end;
  if (bhdr.nvol > 1) then
     nhdr.dim[0]:=4//4D
  else
      nhdr.dim[0]:=3;//3D
  nhdr.dim[1]:=bhdr.nx;
  nhdr.dim[2]:=bhdr.ny;
  nhdr.dim[3]:=bhdr.nz;
  nhdr.dim[4]:=bhdr.nvol;
  nhdr.pixdim[1]:=1.0;
  nhdr.pixdim[2]:=1.0;
  nhdr.pixdim[3]:=1.0;
  nhdr.datatype := kDT_FLOAT32;
  nhdr.vox_offset := sizeof(Tbv_header);
  nhdr.sform_code := 1;
  nhdr.srow_x[0]:=nhdr.pixdim[1];nhdr.srow_x[1]:=0.0;nhdr.srow_x[2]:=0.0;nhdr.srow_x[3]:=0.0;
  nhdr.srow_y[0]:=0.0;nhdr.srow_y[1]:=nhdr.pixdim[2];nhdr.srow_y[2]:=0.0;nhdr.srow_y[3]:=0.0;
  nhdr.srow_z[0]:=0.0;nhdr.srow_z[1]:=0.0;nhdr.srow_z[2]:=-nhdr.pixdim[3];nhdr.srow_z[3]:=0.0;
  convertForeignToNifti(nhdr);
  //nhdr.scl_inter:= 1;
  //nhdr.scl_slope := -1;
  result := true;
end; //nii_readBVox

function nii_readDeltaVision (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
const
     kDV_HEADER_SIZE = 1024;
     kSIG_NATIVE = 49312;
     kSIG_SWAPPED = 41152;
Type
  Tdv_header = packed record //Next: PIC Format Header structure
        nx, ny, nz, datatype : LongInt; //  0,4,8,12
        pad0: array [1..24] of char; //padding 16..39
        xDim,yDim,zDim : single; //40,44,48
        pad1: array [1..40] of char; //padding 52..91
        ExtendedHeaderSize: LongInt; //92
        sig: word; //96
        pad2: array [1..82] of char; //padding 98..179
        numTimes : int32; //180
        pad3: array [1..12] of char;//padding 184..195
        numChannels : word; //196
        pad4: array [1..10] of char;//padding 198..207
        xOri, yOri, zOri: single; //208,212,216
        pad5: array [1..804] of char;//padding 220..1024
        //padding
  end; // Tdv_header;
var
   bhdr : Tdv_header;
   lHdrFile: file;
   sizeZ, sizeT: integer;
begin
  result := false;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading DeltaVision header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  BlockRead(lHdrFile, bhdr, sizeof(Tdv_header));
  CloseFile(lHdrFile);
  if (bhdr.sig <> kSIG_NATIVE) and (bhdr.sig <> kSIG_SWAPPED) then begin //signature not found!
    NSLog('Error in reading DeltaVision file (signature not correct).');
    exit;
  end;
  swapEndian := false;
  if (bhdr.sig = kSIG_SWAPPED) then begin
    swapEndian := true;
    pswap4i(bhdr.nx);
    pswap4i(bhdr.ny);
    pswap4i(bhdr.nz);
    pswap4r(bhdr.xDim);
    pswap4r(bhdr.yDim);
    pswap4r(bhdr.zDim);
    pswap4i(bhdr.ExtendedHeaderSize);
    bhdr.sig := swap(bhdr.sig);
    pswap4i(bhdr.numTimes);
    bhdr.numChannels := swap(bhdr.numChannels);
    pswap4r(bhdr.xOri);
    pswap4r(bhdr.yOri);
    pswap4r(bhdr.zOri);
  end;
  sizeZ := bhdr.nz;
  sizeT := 1;
  if ( bhdr.nz mod (bhdr.numTimes * bhdr.numChannels) = 0 ) then begin
        sizeZ := bhdr.nz div (bhdr.numTimes * bhdr.numChannels);
        sizeT := bhdr.nz div sizeZ;
  end;
  if (sizeT > 1) then
     nhdr.dim[0]:=4//4D
  else
      nhdr.dim[0]:=3;//3D
  nhdr.dim[1]:=bhdr.nx;
  nhdr.dim[2]:=bhdr.ny;
  nhdr.dim[3]:=sizeZ;
  nhdr.dim[4]:=sizeT;
  nhdr.pixdim[1]:=1.0;
  nhdr.pixdim[2]:=1.0;
  nhdr.pixdim[3]:=1.0;
  nhdr.datatype := kDT_UINT16;
  nhdr.vox_offset := kDV_HEADER_SIZE + bhdr.ExtendedHeaderSize;
  nhdr.sform_code := 1;
  nhdr.srow_x[0]:=nhdr.pixdim[1];nhdr.srow_x[1]:=0.0;nhdr.srow_x[2]:=0.0;nhdr.srow_x[3]:=0.0;
  nhdr.srow_y[0]:=0.0;nhdr.srow_y[1]:=nhdr.pixdim[2];nhdr.srow_y[2]:=0.0;nhdr.srow_y[3]:=0.0;
  nhdr.srow_z[0]:=0.0;nhdr.srow_z[1]:=0.0;nhdr.srow_z[2]:=-nhdr.pixdim[3];nhdr.srow_z[3]:=0.0;
  convertForeignToNifti(nhdr);
  result := true;
end; //nii_readDeltaVision

procedure pswap4ui(var s : uint32);
type
  swaptype = packed record
    case byte of
      0:(Word1,Word2 : word); //word is 16 bit
      1:(Long:uint32);
  end;
  swaptypep = ^swaptype;
var
  inguy:swaptypep;
  outguy:swaptype;
begin
  inguy := @s; //assign address of s to inguy
  outguy.Word1 := swap(inguy^.Word2);
  outguy.Word2 := swap(inguy^.Word1);
  s:=outguy.Long;
end; //proc swap4

function nii_readGipl (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
const
     kmagic_number =4026526128;
Type
  Tdv_header = packed record
        dim: array [1..4] of Word;
        data_type: word;
        pixdim: array [1..4] of Single;
        patient: array [1..80] of char;
        matrix: array [1..20] of Single;
        orientation, par2: byte;
        voxmin, voxmax: Double;
        origin: array [1..4] of Double;
        pixval_offset, pixval_cal, interslicegap, user_def2 : single;
        magic_number : uint32;
  end; // Tdv_header;
var
   bhdr : Tdv_header;
   lHdrFile: file;
   i, FSz,FSzX: integer;
begin
  result := false;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading GIPL header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  FSz := Filesize(lHdrFile);
  BlockRead(lHdrFile, bhdr, sizeof(Tdv_header));
  CloseFile(lHdrFile);
  swapEndian := false;
  {$IFNDEF ENDIAN_BIG} //GIPL is big endian, so byte swap on little endian
  swapEndian := true;
  for i := 1 to 4 do begin
      bhdr.dim[i] := swap(bhdr.dim[i]);
      pswap4r(bhdr.pixdim[i]);
      bhdr.origin[i] := swap64r(bhdr.origin[i]);
  end;
  for i := 1 to 20 do
      pswap4r(bhdr.matrix[i]);
  bhdr.data_type := swap(bhdr.data_type);
  bhdr.voxmin := swap64r(bhdr.voxmin);
  bhdr.voxmax := swap64r(bhdr.voxmax);
  pswap4r(bhdr.pixval_offset);
  pswap4r(bhdr.pixval_cal);
  pswap4r(bhdr.interslicegap);
  pswap4r(bhdr.user_def2);
  pswap4ui(bhdr.magic_number);
  {$ENDIF}
  //NSLog(format('%g %g %g %g ', [bhdr.matrix[1],bhdr.matrix[2],bhdr.matrix[3],bhdr.matrix[4]] ));
  if bhdr.magic_number <> kmagic_number then begin
     NSLog('Error in reading GIPL header signature '+inttostr(bhdr.magic_number)+' != '+inttostr(sizeof(Tdv_header)));
     exit;
  end;
  if (bhdr.data_type = 1) then
     nhdr.datatype := kDT_BINARY
  else if (bhdr.data_type = 7) then
       nhdr.datatype := kDT_INT8
  else if (bhdr.data_type = 8) then
       nhdr.datatype := kDT_UNSIGNED_CHAR
  else if (bhdr.data_type = 15) then
       nhdr.datatype := kDT_INT16
  else if (bhdr.data_type = 16) then
       nhdr.datatype := kDT_UINT16
  else if (bhdr.data_type = 31) then
       nhdr.datatype := kDT_UINT32
  else if (bhdr.data_type = 32) then
       nhdr.datatype := kDT_INT32
  else if (bhdr.data_type = 64) then
       nhdr.datatype := kDT_FLOAT32
  else if (bhdr.data_type = 64) then
       nhdr.datatype := kDT_DOUBLE
  else begin
    NSLog('Unsupported GIPL data type '+inttostr(nhdr.datatype));
    exit;
  end;
  for i := 1 to 4 do begin
      if bhdr.dim[i] < 1 then
         bhdr.dim[i] := 1;
       nhdr.dim[i]:=bhdr.dim[i];
       nhdr.pixdim[i]:=bhdr.pixdim[i]
  end;
  if (bhdr.dim[4] > 1) then
     nhdr.dim[0]:=4//4D
  else
     nhdr.dim[0]:=3;//3D
  if bhdr.interslicegap > 0 then
     nhdr.pixdim[3] := bhdr.pixdim[3] + bhdr.interslicegap;
  nhdr.vox_offset := sizeof(Tdv_header);
  nhdr.sform_code := 1;
  nhdr.srow_x[0]:=nhdr.pixdim[1];nhdr.srow_x[1]:=0.0;nhdr.srow_x[2]:=0.0;nhdr.srow_x[3]:=0.0;
  nhdr.srow_y[0]:=0.0;nhdr.srow_y[1]:=nhdr.pixdim[2];nhdr.srow_y[2]:=0.0;nhdr.srow_y[3]:=0.0;
  nhdr.srow_z[0]:=0.0;nhdr.srow_z[1]:=0.0;nhdr.srow_z[2]:=nhdr.pixdim[3];nhdr.srow_z[3]:=0.0;
  convertForeignToNifti(nhdr);
  FSzX := sizeof(Tdv_header) + ( bhdr.dim[1]*bhdr.dim[2]*bhdr.dim[3]*bhdr.dim[4]*(nhdr.bitpix div 8));
  if (nhdr.bitpix <> 1) and (FSz <> FSzX) then begin
     NSLog('Error unexpected file size '+inttostr(FSz)+' != '+inttostr(FSzX));
     exit;
  end;
  result := true;
end; //nii_readGipl

function nii_readpic (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//https://github.com/jefferis/pic2nifti/blob/master/libpic2nifti.c
const
     kBIORAD_HEADER_SIZE  = 76;
     kBIORAD_NOTE_HEADER_SIZE = 16;
     kBIORAD_NOTE_SIZE = 80;
Type
  Tbiorad_header = packed record //Next: PIC Format Header structure
        nx, ny : word;    //  0   2*2     image width and height in pixels
        npic: SmallInt;               //  4   2       number of images in file
        ramp1_min: SmallInt;          //  6   2*2     LUT1 ramp min. and max.
        ramp1_max: SmallInt;
        notes: LongInt;                // 10   4       no notes=0; has notes=non zero
        byte_format: SmallInt;        // 14   2       bytes=TRUE(1); words=FALSE(0)
        n : word;         // 16   2       image number within file
        name: array [1..32] of char;            // 18   32      file name
        merged: SmallInt;             // 50   2       merged format
        color1 : word;    // 52   2       LUT1 color status
        file_id : word;   // 54   2       valid .PIC file=12345
        ramp2_min: SmallInt;          // 56   2*2     LUT2 ramp min. and max.
        ramp2_max: SmallInt;
        color2: word;    // 60   2       LUT2 color status
        edited: SmallInt;             // 62   2       image has been edited=TRUE(1)
        lens: SmallInt;               // 64   2       Integer part of lens magnification
        mag_factor: single;         // 66   4       4 byte real mag. factor (old ver.)
        dummy1, dummy2, dummy3: word;  // 70   6       NOT USED (old ver.=real lens mag.)
     end; // biorad_header;
    Tbiorad_note_header = packed record
      blank: SmallInt;		// 0	2
      note_flag: LongInt;		// 2	4
      blank2: LongInt;			// 6	4
      note_type: SmallInt;	// 10	2
      blank3: LongInt;			// 12	4
      note: array[1..kBIORAD_NOTE_SIZE] of char;
    end;//biorad_note_header;
var
   bhdr : Tbiorad_header;
   nh: Tbiorad_note_header;
   lHdrFile: file;
   //s: string;
   i, bytesHdrImg, nNotes: integer;
begin
  result := false;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading BioRad PIC header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  BlockRead(lHdrFile, bhdr, sizeof(Tbiorad_header));
  if (bhdr.file_id <> 12345) then begin //signature not found!
    CloseFile(lHdrFile);
    NSLog('Error in reading BioRad PIC header file ID not 12345.');
    exit;
  end;
  {$IFDEF ENDIAN_BIG}
  swapEndian := true;
  bhdr.nx := swap(bhdr.nx);
  bhdr.ny := swap(bhdr.ny);
  bhdr.npic := swap(bhdr.npic);
  bhdr.byte_format := swap(bhdr.byte_format);
  {$ENDIF}
  nhdr.dim[0]:=3;//3D
  nhdr.dim[1]:=bhdr.nx;
  nhdr.dim[2]:=bhdr.ny;
  nhdr.dim[3]:=bhdr.npic;
  nhdr.dim[4]:=1;
  nhdr.pixdim[1]:=1.0;
  nhdr.pixdim[2]:=1.0;
  nhdr.pixdim[3]:=1.0;
  if (bhdr.byte_format = 1) then
      nhdr.datatype := kDT_UINT8 // 2
  else
      nhdr.datatype := kDT_UINT16;
  nhdr.vox_offset := kBIORAD_HEADER_SIZE;
  bytesHdrImg := sizeof(Tbiorad_header)+bhdr.nx*bhdr.ny*bhdr.npic*bhdr.byte_format;
  nNotes := (Filesize(lHdrFile) - bytesHdrImg) div (kBIORAD_NOTE_HEADER_SIZE+kBIORAD_NOTE_SIZE);
  if (nNotes > 0) then begin
     seek(lHdrFile, bytesHdrImg);
     for i := 1 to nNotes do begin
         BlockRead(lHdrFile, nh, sizeof(Tbiorad_note_header));
         {$IFDEF ENDIAN_BIG}
         nh.note_type := swap(nh.note_type);
         {$ENDIF}
         if(nh.note_type=1) then continue; // These are not interesting notes
         if AnsiStartsStr('AXIS_2 ', nh.note) then
             nhdr.pixdim[1]  := parsePicString(nh.note);
         if AnsiStartsStr('AXIS_3 ', nh.note) then
             nhdr.pixdim[2]  := parsePicString(nh.note);
         if AnsiStartsStr('AXIS_4 ', nh.note) then
             nhdr.pixdim[3]  := parsePicString(nh.note);
     end;
  end;
  CloseFile(lHdrFile);
  nhdr.sform_code := 1;
  nhdr.srow_x[0]:=nhdr.pixdim[1];nhdr.srow_x[1]:=0.0;nhdr.srow_x[2]:=0.0;nhdr.srow_x[3]:=0.0;
  nhdr.srow_y[0]:=0.0;nhdr.srow_y[1]:=nhdr.pixdim[2];nhdr.srow_y[2]:=0.0;nhdr.srow_y[3]:=0.0;
  nhdr.srow_z[0]:=0.0;nhdr.srow_z[1]:=0.0;nhdr.srow_z[2]:=-nhdr.pixdim[3];nhdr.srow_z[3]:=0.0;
  convertForeignToNifti(nhdr);
  result := true;
end;

function nii_readEcat(var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
Const
  ECAT7_BYTE =1;
  ECAT7_VAXI2 =2;
  ECAT7_VAXI4 =3;
  ECAT7_VAXR4 =4;
  ECAT7_IEEER4 =5;
  ECAT7_SUNI2 =6;
  ECAT7_SUNI4 =7;
  //image types
  ECAT7_2DSCAN =1;
  ECAT7_IMAGE16 =2;
  ECAT7_ATTEN =3;
  ECAT7_2DNORM =4;
  ECAT7_POLARMAP =5;
  ECAT7_VOLUME8 =6;
  ECAT7_VOLUME16 =7;
  ECAT7_PROJ =8;
  ECAT7_PROJ16 =9;
  ECAT7_IMAGE8 =10;
  ECAT7_3DSCAN =11;
  ECAT7_3DSCAN8 =12;
  ECAT7_3DNORM =13;
  ECAT7_3DSCANFIT =14;
Label
  666;
Type
  THdrMain = packed record //Next: MGH Format Header structure
    magic: array[1..14] of char;
    original_filename: array[1..32] of char;
    sw_version, system_type, file_type: uint16;
    serial_number: array[1..10] of char;
    scan_start_time: uint32;
    isotope_name: array[1..8] of char;
    isotope_halflife: single;
    radiopharmaceutical: array[1..32] of char;
    gantry_tilt, gantry_rotation, bed_elevation, intrinsic_tilt: single;
    wobble_speed, transm_source_type: int16;
    distance_scanned, transaxial_fov: single;
    angular_compression, coin_samp_mode, axial_samp_mode: uint16;
    ecat_calibration_factor: single;
    calibration_unitS, calibration_units_type, compression_code: uint16;
    study_type: array[1..12] of char;
    patient_id: array[1..16] of char;
    patient_name: array[1..32] of char;
    patient_sex, patient_dexterity: char;
    patient_age, patient_height, patient_weight: single;
    patient_birth_date: uint32;
    physician_name, operator_name, study_description: array[1..32] of char;
    acquisition_type, patient_orientation: uint16;
    facility_name: array[1..20] of char;
    num_planes, num_frames, num_gates, num_bed_pos: uint16;
    init_bed_position: single;
    bed_position: array[1..15] of single;
    plane_separation: single;
    lwr_sctr_thres, lwr_true_thres, upr_true_thres: uint16;
    user_process_code: array[1..10] of char;
    acquisition_mode: uint16;
    bin_size, branching_fraction: single;
    dose_start_time: single;
    dosage, well_counter_corr_factor: single;
    data_units: array[1..32] of char;
    septa_state: uint16;
    fill: array[1..12] of char;
  end;
  THdrList = packed record
        hdr,
        r01,r02,r03,r04,r05,r06,r07,r08,r09,r10,
        r11,r12,r13,r14,r15,r16,r17,r18,r19,r20,
        r21,r22,r23,r24,r25,r26,r27,r28,r29,r30,
        r31 : array[1..4] of int32;
    end;
  THdrImg = packed record
    data_type, num_dimensions, x_dimension, y_dimension, z_dimension: smallint;
    x_offset, y_offset, z_offset, recon_zoom, scale_factor: single;
    image_min, image_max: smallint;
    x_pixel_size, y_pixel_size, z_pixel_size: single;
    frame_duration, frame_start_time,filter_code: smallint;
    x_resolution, y_resolution, z_resolution, num_r_elements, num_angles, z_rotation_angle, decay_corr_fctr: single;
    processing_code, gate_duration, r_wave_offset, num_accepted_beats: int32;
    filter_cutoff_frequenc, filter_resolution, filter_ramp_slope: single;
    filter_order: smallint;
    filter_scatter_fraction, filter_scatter_slope: single;
    annotation: string[40];
    mtx: array [1..9] of single;
    rfilter_cutoff, rfilter_resolution: single;
    rfilter_code, rfilter_order: int16;
    zfilter_cutoff, zfilter_resolution: single;
    zfilter_code, zfilter_order: smallint;
    mtx_1_4, mtx_2_4, mtx_3_4: single;
    scatter_type, recon_type, recon_views: smallint;
    fill_cti: array [1..87] of int16;
    fill_user: array [1..49] of int16;
  end;
var
  mhdr: THdrMain;
  ihdr: THdrImg;
  lhdr: THdrList;
  lHdrFile: file;
  img1_StartBytes: integer;
begin
  result := false;
  gzBytes := 0;
  {$I-}
  AssignFile(lHdrFile, fname);
  FileMode := fmOpenRead;  //Set file access to read only
  Reset(lHdrFile, 1);
  {$I+}
  if ioresult <> 0 then begin
        NSLog('Error in reading ECAT header.'+inttostr(IOResult));
        FileMode := 2;
        exit;
  end;
  BlockRead(lHdrFile, mhdr, sizeof(mhdr));
  {$IFDEF FPC} mhdr.magic:=upcase(mhdr.magic); {$ENDIF} //Delphi 7 can not upcase arrays
  if ((mhdr.magic[1] <> 'M') or (mhdr.magic[2] <> 'A') or (mhdr.magic[3] <> 'T') or (mhdr.magic[4] <> 'R') or (mhdr.magic[5] <> 'I') or (mhdr.magic[6] <> 'X')) then
       goto 666;
  {$IFDEF ENDIAN_BIG} //data always stored big endian
    swapEndian := false;
  {$ELSE}
    swapEndian := true;
    mhdr.sw_version := swap2(mhdr.sw_version);
    mhdr.file_type := swap2(mhdr.file_type);
    mhdr.num_frames := swap2(mhdr.num_frames);
    pswap4r(mhdr.ecat_calibration_factor);
  {$ENDIF}
  if ((mhdr.file_type < ECAT7_2DSCAN) or (mhdr.file_type > ECAT7_3DSCANFIT)) then begin
      ShowMsg('Unknown ECAT file type '+ inttostr( mhdr.file_type));
      goto 666;
  end;
  //read list header
  BlockRead(lHdrFile, lhdr, sizeof(lhdr));
  {$IFNDEF ENDIAN_BIG} //data always stored big endian
  pswap4i(lhdr.r01[2]);
  {$ENDIF}
  img1_StartBytes := lhdr.r01[2] * 512;
  //read image header
  seek(lHdrFile, img1_StartBytes - 512);
  BlockRead(lHdrFile, ihdr, sizeof(ihdr));
  {$IFNDEF ENDIAN_BIG} //data always stored big endian
  ihdr.data_type := swap(ihdr.data_type);
  pswap4r(ihdr.x_pixel_size);
  pswap4r(ihdr.y_pixel_size);
  pswap4r(ihdr.z_pixel_size);
  pswap4r(ihdr.scale_factor);
  ihdr.x_dimension := swap(ihdr.x_dimension);
  ihdr.y_dimension := swap(ihdr.y_dimension);
  ihdr.z_dimension := swap(ihdr.z_dimension);
  {$ENDIF}
  ihdr.x_pixel_size := ihdr.x_pixel_size * 10.0;
  ihdr.y_pixel_size := ihdr.y_pixel_size * 10.0;
  ihdr.z_pixel_size := ihdr.z_pixel_size * 10.0;
  if ((ihdr.data_type <> ECAT7_BYTE) and (ihdr.data_type <> ECAT7_SUNI2) and (ihdr.data_type <> ECAT7_SUNI4)) then begin
      ShowMsg('Unknown ECAT data type '+ inttostr(ihdr.data_type));
      goto 666;
  end;
  nhdr.scl_slope := ihdr.scale_factor * mhdr.ecat_calibration_factor;
  nhdr.datatype := kDT_INT16;
  if (ihdr.data_type = ECAT7_BYTE) then
        nhdr.datatype := kDT_UINT8
  else if (ihdr.data_type = ECAT7_SUNI4)  then
       nhdr.datatype := kDT_INT32;
  nhdr.dim[1]:=ihdr.x_dimension;
  nhdr.dim[2]:=ihdr.y_dimension;
  nhdr.dim[3]:=ihdr.z_dimension;
  nhdr.dim[4]:=1;
  nhdr.pixdim[1]:=ihdr.x_pixel_size;
  nhdr.pixdim[2]:=ihdr.y_pixel_size;
  nhdr.pixdim[3]:=ihdr.z_pixel_size;
  nhdr.vox_offset := img1_StartBytes;
  nhdr.sform_code := 0;
  nhdr.srow_x[0]:=nhdr.pixdim[1]; nhdr.srow_x[1]:=0; nhdr.srow_x[2]:=0; nhdr.srow_x[3]:=-(ihdr.x_dimension-2.0)/2.0*ihdr.x_pixel_size;
  nhdr.srow_y[0]:=0; nhdr.srow_y[1]:=nhdr.pixdim[2]; nhdr.srow_y[2]:=0; nhdr.srow_y[3]:=-(ihdr.y_dimension-2.0)/2.0*ihdr.y_pixel_size;
  nhdr.srow_z[0]:=0; nhdr.srow_z[1]:=0; nhdr.srow_z[2]:=nhdr.pixdim[3]; nhdr.srow_z[3]:=-(ihdr.z_dimension-2.0)/2.0*ihdr.z_pixel_size;
  convertForeignToNifti(nhdr);
  result := true;
666:
CloseFile(lHdrFile);
end;

function readMGHHeader (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
Type
  Tmgh = packed record //Next: MGH Format Header structure
   version, width,height,depth,nframes,mtype,dof : longint;
   goodRASFlag: smallint;
   spacingX,spacingY,spacingZ,xr,xa,xs,yr,ya,ys,zr,za,zs,cr,ca,cs: single;
  end;
var
  mgh: Tmgh;
  lBuff: Bytep;
  lExt: string;
  lHdrFile: file;
	PxyzOffset, Pcrs: vect4;
  i,j: integer;
  base: single;
  m: mat44;
begin
  result := false;
  lExt := UpCaseExt(fname);
  if (lExt = '.MGZ') then begin
	  lBuff := @mgh;
	  UnGZip(fname,lBuff,0,sizeof(Tmgh)); //1388
    gzBytes := K_gzBytes_headerAndImageCompressed;
  end else begin //if MGZ, else assume uncompressed MGH
     gzBytes := 0;
	   {$I-}
	   AssignFile(lHdrFile, fname);
	   FileMode := fmOpenRead;  //Set file access to read only
	   Reset(lHdrFile, 1);
	   {$I+}
	   if ioresult <> 0 then begin
		  NSLog('Error in reading MGH header.'+inttostr(IOResult));
		  FileMode := 2;
		  exit;
	   end;
	   BlockRead(lHdrFile, mgh, sizeof(Tmgh));
	   CloseFile(lHdrFile);
  end;
  {$IFDEF ENDIAN_BIG} //data always stored big endian
    swapEndian := false;
  {$ELSE}
    swapEndian := true;
    swap4(mgh.version);
    swap4(mgh.width);
    swap4(mgh.height);
    swap4(mgh.depth);
    swap4(mgh.nframes);
    swap4(mgh.mtype);
    swap4(mgh.dof);
    mgh.goodRASFlag := swap(mgh.goodRASFlag);
    Xswap4r(mgh.spacingX);
    Xswap4r(mgh.spacingY);
    Xswap4r(mgh.spacingZ);
    Xswap4r(mgh.xr);
    Xswap4r(mgh.xa);
    Xswap4r(mgh.xs);
    Xswap4r(mgh.yr);
    Xswap4r(mgh.ya);
    Xswap4r(mgh.ys);
    Xswap4r(mgh.zr);
    Xswap4r(mgh.za);
    Xswap4r(mgh.zs);
    Xswap4r(mgh.cr);
    Xswap4r(mgh.ca);
    Xswap4r(mgh.cs);
  {$ENDIF}
  if ((mgh.version <> 1) or (mgh.mtype < 0) or (mgh.mtype > 4)) then begin
        NSLog('Error: first value in a MGH header should be 1 and data type should be in the range 1..4.');
        exit;
  end;
  if (mgh.mtype = 0) then
        nhdr.datatype := kDT_UINT8
  else if (mgh.mtype = 4)  then
        nhdr.datatype := kDT_INT16
  else if (mgh.mtype = 1)  then
        nhdr.datatype := kDT_INT32
  else if (mgh.mtype = 3)  then
        nhdr.datatype := kDT_FLOAT32;
  if ((mgh.width > 32767) or (mgh.height > 32767) or (mgh.depth > 32767) or (mgh.nframes > 32767)) then begin
     //MGH datasets can be huge 1D streams, see https://github.com/vistalab/vistasoft/tree/master/fileFilters/freesurfer
        NSLog('Error: this software limits rows/columns/slices/volumes to 32767 or less.');
        exit;
  end;
  nhdr.dim[1]:=mgh.width;
  nhdr.dim[2]:=mgh.height;
  nhdr.dim[3]:=mgh.depth;
	nhdr.dim[4]:=mgh.nframes;
	nhdr.pixdim[1]:=mgh.spacingX;
	nhdr.pixdim[2]:=mgh.spacingY;
	nhdr.pixdim[3]:=mgh.spacingZ;
	nhdr.vox_offset := 284;
	nhdr.sform_code := 1;
	//convert MGH to NIfTI transform see Bruce Fischl mri.c MRIxfmCRS2XYZ https://github.com/neurodebian/freesurfer/blob/master/utils/mri.c
	LOAD_MAT44(m,mgh.xr*nhdr.pixdim[1],mgh.yr*nhdr.pixdim[2],mgh.zr*nhdr.pixdim[3],0,
               mgh.xa*nhdr.pixdim[1],mgh.ya*nhdr.pixdim[2],mgh.za*nhdr.pixdim[3],0,
			         mgh.xs*nhdr.pixdim[1],mgh.ys*nhdr.pixdim[2],mgh.zs*nhdr.pixdim[3],0);
  base := 0.0; //0 or 1: are voxels indexed from 0 or 1?
	Pcrs[0] := (nhdr.dim[1]/2.0)+base;
	Pcrs[1] := (nhdr.dim[2]/2.0)+base;
	Pcrs[2] := (nhdr.dim[3]/2.0)+base;
	Pcrs[3] := 1;
	for i:=0 to 3 do begin //multiply Pcrs * m
		PxyzOffset[i] := 0;
		for j := 0 to 3 do
			PxyzOffset[i] := PxyzOffset[i]+ (m[i,j]*Pcrs[j]);
	end;
  nhdr.srow_x[0]:=m[0,0]; nhdr.srow_x[1]:=m[0,1]; nhdr.srow_x[2]:=m[0,2]; nhdr.srow_x[3]:=mgh.cr - PxyzOffset[0];
	nhdr.srow_y[0]:=m[1,0]; nhdr.srow_y[1]:=m[1,1]; nhdr.srow_y[2]:=m[1,2]; nhdr.srow_y[3]:=mgh.ca - PxyzOffset[1];
	nhdr.srow_z[0]:=m[2,0]; nhdr.srow_z[1]:=m[2,1]; nhdr.srow_z[2]:=m[2,2]; nhdr.srow_z[3]:=mgh.cs - PxyzOffset[2];
  convertForeignToNifti(nhdr);
  result := true;
end;

procedure splitStr(delimiter: char; str: string; mArray: TStrings);
begin
  mArray.Clear;
  mArray.Delimiter := delimiter;
  mArray.DelimitedText := str;
end;

procedure splitStrStrict(delimiter: char; S: string; sl: TStrings);
begin
  sl.Clear;
  sl.Delimiter := delimiter;
  sl.DelimitedText := '"' + StringReplace(S, sl.Delimiter, '"' + sl.Delimiter + '"', [rfReplaceAll]) + '"';
end;

function cleanStr (S:string): string; // "(12.31)" ->"12.31"
begin
  result := StringReplace(S, '(', '', [rfReplaceAll]);
  result := StringReplace(result, ')', '', [rfReplaceAll]);
end;

type TFByte =  File of Byte;
(*procedure ReadLnBin(var f: TFByte; var s: string);
const
  kEOLN = $0A;
var
   bt : Byte;
begin
     s := '';
     while (not  EOF(f)) do begin
           Read(f,bt);
           if bt = kEOLN then exit;
           s := s + Chr(bt);
     end;
end; *)
  function ReadLnBin(var f: TFByte; var s: string): boolean;
  const
    kEOLN = $0A;
  var
     bt : Byte;
  begin
       s := '';
       if EOF(f) then exit(false);
       while (not  EOF(f)) do begin
             Read(f,bt);
             if bt = kEOLN then exit;
             s := s + Chr(bt);
       end;
       exit(true);
  end;

function readVTKHeader (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//VTK Simple Legacy Formats : STRUCTURED_POINTS : BINARY
// http://daac.hpc.mil/gettingStarted/VTK_DataFormats.html
// https://github.com/bonilhamusclab/MRIcroS/blob/master/%2BfileUtils/%2Bvtk/readVtk.m
// http://www.ifb.ethz.ch/education/statisticalphysics/file-formats.pdf
// ftp://ftp.tuwien.ac.at/visual/vtk/www/FileFormats.pdf
//  "The VTK data files described here are written in big endian form"
label
   666;
var
   f: TFByte;//TextFile;
   strlst: TStringList;
   str: string;
   i, num_vox: integer;
begin
  gzBytes := 0;
  {$IFDEF ENDIAN_BIG}
  swapEndian := false;
  {$ELSE}
  swapEndian := true;
  {$ENDIF}
  result := false;
  strlst:=TStringList.Create;
  AssignFile(f, fname);
  FileMode := fmOpenRead;
  {$IFDEF FPC} Reset(f,1); {$ELSE} Reset(f); {$ENDIF}
  ReadLnBin(f, str); //signature: '# vtk DataFile'
  if pos('VTK', UpperCase(str)) <> 3 then begin
    showmessage('Not a VTK file');
    goto 666;
  end;
  ReadLnBin(f, str); //comment: 'Comment: created with MRIcroS'
  ReadLnBin(f, str); //kind: 'BINARY' or 'ASCII'
  if pos('BINARY', UpperCase(str)) <> 1 then begin  // '# vtk DataFile'
     showmessage('Only able to read binary VTK file:'+str);
     goto 666;
  end;
  ReadLnBin(f, str); // kind, e.g. "DATASET POLYDATA" or "DATASET STRUCTURED_ POINTS"
  if pos('STRUCTURED_POINTS', UpperCase(str)) = 0 then begin
    showmessage('Only able to read VTK images saved as STRUCTURED_POINTS, not '+ str);
    goto 666;
  end;
  while (str <> '') and (pos('POINT_DATA', UpperCase(str)) = 0) do begin
    ReadLnBin(f, str);
    strlst.DelimitedText := str;
    if pos('DIMENSIONS', UpperCase(str)) <> 0 then begin //e.g. "DIMENSIONS 128 128 128"
       nhdr.dim[1] := StrToIntDef(strlst[1],1);
       nhdr.dim[2] := StrToIntDef(strlst[2],1);
       nhdr.dim[3] := StrToIntDef(strlst[3],1);
    end; //dimensions
    if (pos('ASPECT_RATIO', UpperCase(str)) <> 0) or (pos('SPACING', UpperCase(str)) <> 0) then begin //e.g. "ASPECT_RATIO 1.886 1.886 1.913"
      nhdr.pixdim[1] := StrToFloatDef(strlst[1],1);
      nhdr.pixdim[2] := StrToFloatDef(strlst[2],1);
      nhdr.pixdim[3] := StrToFloatDef(strlst[3],1);
      //showmessage(format('%g %g %g',[nhdr.pixdim[1], nhdr.pixdim[2], nhdr.pixdim[3] ]));
    end; //aspect ratio
    if (pos('ORIGIN', UpperCase(str)) <> 0) then begin //e.g. "ASPECT_RATIO 1.886 1.886 1.913"
      nhdr.srow_x[3] := -StrToFloatDef(strlst[1],1);
      nhdr.srow_y[3] := -StrToFloatDef(strlst[2],1);
      nhdr.srow_z[3] := -StrToFloatDef(strlst[3],1);
      //showmessage(format('%g %g %g',[nhdr.pixdim[1], nhdr.pixdim[2], nhdr.pixdim[3] ]));
    end; //aspect ratio
  end; //not POINT_DATA
  if pos('POINT_DATA', UpperCase(str)) = 0 then goto 666;
  num_vox :=  StrToIntDef(strlst[1],0);
  if num_vox <> (nhdr.dim[1] * nhdr.dim[2] * nhdr.dim[3]) then begin
     showmessage(format('Expected POINT_DATA to equal %dx%dx%d',[nhdr.dim[1], nhdr.dim[2], nhdr.dim[3] ]));
     goto 666;
  end;
  ReadLnBin(f, str);
  if pos('SCALARS', UpperCase(str)) = 0 then goto 666; //"SCALARS scalars unsigned_char"
  strlst.DelimitedText := str;
  str := UpperCase(strlst[2]);
  //dataType is one of the types bit, unsigned_char, char, unsigned_short, short, unsigned_int, int, unsigned_long, long, float, or double
  if pos('UNSIGNED_CHAR', str) <> 0 then
      nhdr.datatype := kDT_UINT8 //
  else if pos('SHORT', str) <> 0 then
       nhdr.datatype := kDT_INT16 //
  else if pos('UNSIGNED_SHORT', str) <> 0 then
       nhdr.datatype := kDT_UINT16 //
  else if pos('INT', str) <> 0 then
       nhdr.datatype := kDT_INT32 //
  else  if pos('FLOAT', str) <> 0 then
      nhdr.datatype := kDT_FLOAT
  else  if pos('DOUBLE', str) <> 0 then
      nhdr.datatype := kDT_DOUBLE
  else begin
        showmessage('Unknown VTK scalars type '+str);
        goto 666;
  end;
  convertForeignToNifti(nhdr);
  //showmessage(inttostr(nhdr.datatype));
  ReadLnBin(f, str);
  if pos('LOOKUP_TABLE', UpperCase(str)) = 0 then goto 666; //"LOOKUP_TABLE default"
  nhdr.vox_offset := filepos(f);
  //fill matrix
  for i := 0 to 2 do begin
    nhdr.srow_x[i] := 0;
    nhdr.srow_y[i] := 0;
    nhdr.srow_z[i] := 0;
  end;
  nhdr.srow_x[0] := nhdr.pixdim[1];
  nhdr.srow_y[1] := nhdr.pixdim[2];
  nhdr.srow_z[2] := nhdr.pixdim[3];
  //showmessage('xx' +inttostr( filepos(f) ));
  result := true;
  666:
  closefile(f);
  strlst.Free;
end;

function readMHAHeader (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//Read VTK "MetaIO" format image
//http://www.itk.org/Wiki/ITK/MetaIO/Documentation#Reading_a_Brick-of-Bytes_.28an_N-Dimensional_volume_in_a_single_file.29
//https://www.assembla.com/spaces/plus/wiki/Sequence_metafile_format
//http://itk-insight-users.2283740.n2.nabble.com/MHA-MHD-File-Format-td7585031.html
var
  FP: TextFile;
  str, tagName, elementNames: string;
  ch: char;
  isLocal,compressedData: boolean;
  matOrient, mat, d, t: mat33;
  //compressedDataSize,
  nPosition, nOffset, matElements, matElementsOrient,  headerSize, nItems, nBytes, i, channels, fileposBytes: longint;
  //elementSize,
  offset,position: array [0..3] of single;
  transformMatrix: array [0..11] of single;
  mArray: TStringList;
begin
  result := false;
  if not FileExists(fname) then exit;
    {$IFDEF FPC}
  DefaultFormatSettings.DecimalSeparator := '.' ;
   // DecimalSeparator := '.';
  {$ELSE}
  DecimalSeparator := '.';
  {$ENDIF}
  for i := 0 to 3 do begin
      position[i] := 0;
      offset[i] := 0;
      //elementSize[i] := 1;
  end;
  nPosition := 0;
  nOffset := 0;
  gzBytes := 0;
  fileposBytes := 0;
  //compressedDataSize := 0;
  swapEndian := false;
  isLocal := true; //image and header embedded in same file, if false detached image
  headerSize := 0;
  matElements := 0;
  matElementsOrient := 0;
  compressedData := false;
  mArray := TStringList.Create;
  Filemode := fmOpenRead;
  AssignFile(fp,fname);
  reset(fp);
  while not EOF(fp) do begin
    str := '';
    while not EOF(fp) do begin
      read(fp,ch);
      inc(fileposBytes);
      if (ch = chr($0D)) or (ch = chr($0A)) then break;
      str := str+ch;
    end;
    if (length(str) < 1) or (str[1]='#') then continue;
    splitstrStrict('=',str,mArray);
    if (mArray.count < 2) then continue;
    tagName := cleanStr(mArray[0]);
    elementNames := mArray[1];
    splitstr(',',elementNames,mArray);
    nItems :=mArray.count;
    if (nItems < 1) then continue;
    for i := 0 to (nItems-1) do
      mArray[i] := cleanStr(mArray[i]); //remove '(' and ')',
    if AnsiContainsText(tagName, 'ObjectType') and (not AnsiContainsText(mArray.Strings[0], 'Image')) then begin
        NSLog('Expecting file with tag "ObjectType = Image" instead of "ObjectType = '+mArray.Strings[0]+'"');

    end {else if AnsiContainsText(tagName, 'NDims') then begin
            nDims := strtoint(mArray[0]);
            if (nDims > 4) then begin
                NSLog('Warning: only reading first 4 dimensions');
                nDims := 4;
            end;
    end} else if AnsiContainsText(tagName, 'BinaryDataByteOrderMSB') then begin
            {$IFDEF ENDIAN_BIG} //data always stored big endian
            if not AnsiContainsText(mArray[0], 'True') then swapEndian := true;
            {$ELSE}
            if AnsiContainsText(mArray[0], 'True') then swapEndian := true;
            {$ENDIF}
    end {else if AnsiContainsText(tagName, 'BinaryData') then begin
            if AnsiContainsText(mArray[0], 'True') then binaryData := true;
    end else if AnsiContainsText(tagName, 'CompressedDataSize') then begin
            compressedDataSize := strtoint(mArray[0]);
        end} else if AnsiContainsText(tagName, 'CompressedData') then begin
            if AnsiContainsText(mArray[0], 'True') then
                compressedData := true;
        end  else if AnsiContainsText(tagName, 'Orientation') and (not AnsiContainsText(tagName, 'Anatomical') ) then begin
            if (nItems > 12) then nItems := 12;
            matElementsOrient := nItems;
            for i := 0 to (nItems-1) do
              transformMatrix[i] :=  strtofloat(mArray[i]);


            if (matElementsOrient >= 12) then
                LOAD_MAT33(matOrient, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                           transformMatrix[4],transformMatrix[5],transformMatrix[6],
                           transformMatrix[8],transformMatrix[9],transformMatrix[10])
            else if (matElementsOrient >= 9) then
                LOAD_MAT33(matOrient, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                           transformMatrix[3],transformMatrix[4],transformMatrix[5],
                           transformMatrix[6],transformMatrix[7],transformMatrix[8]);

        end else if AnsiContainsText(tagName, 'TransformMatrix') then begin
            if (nItems > 12) then nItems := 12;
            matElements := nItems;
            for i := 0 to (nItems-1) do
              transformMatrix[i] :=  strtofloat(mArray[i]);
            if (matElements >= 12) then
                LOAD_MAT33(mat, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                           transformMatrix[4],transformMatrix[5],transformMatrix[6],
                           transformMatrix[8],transformMatrix[9],transformMatrix[10])
            else if (matElements >= 9) then
                LOAD_MAT33(mat, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                           transformMatrix[3],transformMatrix[4],transformMatrix[5],
                           transformMatrix[6],transformMatrix[7],transformMatrix[8]);
        end else if AnsiContainsText(tagName, 'Position') then begin
            if (nItems > 3) then nItems := 3;
            nPosition := nItems;
            for i := 0 to (nItems-1) do
              position[i] :=  strtofloat(mArray[i]);
        end else if AnsiContainsText(tagName, 'Offset') then begin
            if (nItems > 3) then nItems := 3;
            nOffset := nItems;
            for i := 0 to (nItems-1) do
              offset[i] :=  strtofloat(mArray[i]);
        end else if AnsiContainsText(tagName, 'AnatomicalOrientation') then begin
            //e.g. RAI
        end else if AnsiContainsText(tagName, 'ElementSpacing') then begin
            if (nItems > 4) then nItems := 4;
            for i := 0 to (nItems-1) do
                nhdr.pixdim[i+1] := strtofloat(mArray[i]);
        end else if AnsiContainsText(tagName, 'DimSize') then begin
            if (nItems > 4) then nItems := 4;
            for i := 0 to (nItems-1) do
                nhdr.dim[i+1] :=  strtoint(mArray[i]);
        end else if AnsiContainsText(tagName, 'HeaderSize') then begin
            headerSize := strtoint(mArray[0]);
        end else if AnsiContainsText(tagName, 'ElementSize') then begin
            //if (nItems > 4) then nItems := 4;
            //for i := 0 to (nItems-1) do
            //    elementSize[i] := strtofloat(mArray[i]);
        end else if AnsiContainsText(tagName, 'ElementNumberOfChannels') then begin
            channels := strtoint(mArray[0]);
            if (channels > 1) then NSLog('Unable to read MHA/MHD files with multiple channels ');
        end else if AnsiContainsText(tagName, 'ElementByteOrderMSB') then begin
            {$IFDEF ENDIAN_BIG} //data always stored big endian
            if not AnsiContainsText(mArray[0], 'True') then swapEndian := true;
            {$ELSE}
            if AnsiContainsText(mArray[0], 'True') then swapEndian := true;
            {$ENDIF}
        end else if AnsiContainsText(tagName, 'ElementType') then begin

            //convert metaImage format to NIfTI http://portal.nersc.gov/svn/visit/tags/2.2.1/vendor_branches/vtk/src/IO/vtkMetaImageWriter.cxx
            //set NIfTI datatype http://nifti.nimh.nih.gov/pub/dist/src/niftilib/nifti1.h
            if AnsiContainsText(mArray[0], 'MET_UCHAR') then
                nhdr.datatype := kDT_UINT8 //
            else if AnsiContainsText(mArray[0], 'MET_CHAR') then
                nhdr.dataType := kDT_INT8 //
            else if AnsiContainsText(mArray[0], 'MET_SHORT') then
                nhdr.dataType := kDT_INT16 //
            else if AnsiContainsText(mArray[0], 'MET_USHORT') then
                nhdr.dataType := kDT_UINT16 //
            else if AnsiContainsText(mArray[0], 'MET_INT') then
                nhdr.dataType := kDT_INT32 //DT_INT32
            else if AnsiContainsText(mArray[0], 'MET_UINT') then
                nhdr.dataType := kDT_UINT32 //DT_UINT32
            else if AnsiContainsText(mArray[0], 'MET_ULONG') then
                nhdr.dataType := kDT_UINT64 //DT_UINT64
            else if AnsiContainsText(mArray[0], 'MET_LONG') then
                nhdr.dataType := kDT_INT64 //DT_INT64
            else if AnsiContainsText(mArray[0], 'MET_FLOAT') then
                nhdr.dataType := kDT_FLOAT32 //DT_FLOAT32
            else if AnsiContainsText(mArray[0], 'MET_DOUBLE') then
                nhdr.dataType := kDT_DOUBLE; //DT_FLOAT64
        end else if AnsiContainsText(tagName, 'ElementDataFile') then begin
            if not AnsiContainsText(mArray[0], 'local') then begin
                str := mArray.Strings[0];
                if fileexists(str) then
                  fname := str
                else begin
                  fname := ExtractFilePath(fname)+str;
                end;
                isLocal := false;
            end;
            break;
        end;
  end; //while reading
  if (headerSize = 0) and (isLocal) then headerSize :=fileposBytes; //!CRAP 2015
  nhdr.vox_offset := headerSize;
  CloseFile(FP);
  Filemode := 2;
  mArray.free;
  //convert transform
  if (matElements >= 9) or (matElementsOrient >= 9) then begin
    //report_Mat(matOrient);
    LOAD_MAT33(d,  nhdr.pixdim[1],0,0,
                 0, nhdr.pixdim[2],0,
                 0,0, nhdr.pixdim[3]);
      if (matElements >= 9) then
         t := nifti_mat33_mul( d, mat)
      else
          t := nifti_mat33_mul( d, matOrient) ;
      if nPosition > nOffset then begin
          offset[0] := position[0];
          offset[1] := position[1];
          offset[2] := position[2];

      end;
      nhdr.srow_x[0] := -t[0,0];
      nhdr.srow_x[1] := -t[1,0];
      nhdr.srow_x[2] := -t[2,0];
      nhdr.srow_x[3] := -offset[0];
      nhdr.srow_y[0] := -t[0,1];
      nhdr.srow_y[1] := -t[1,1];
      nhdr.srow_y[2] := -t[2,1];
      nhdr.srow_y[3] := -offset[1];
      nhdr.srow_z[0] := t[0,2];
      nhdr.srow_z[1] := t[1,2];
      nhdr.srow_z[2] := t[2,2];
      nhdr.srow_z[3] := offset[2];
  end else begin
      //NSLog('Warning: unable to determine image orientation (unable to decode metaIO "TransformMatrix" tag)')};
      nhdr.sform_code:=0;
      nhdr.srow_x[0] := 0;
      nhdr.srow_x[1] := 0;
      nhdr.srow_x[2] := 0;
  end;
  //end transform
  convertForeignToNifti(nhdr);
  if (compressedData) then
      gzBytes := K_gzBytes_onlyImageCompressed;
  if (nhdr.vox_offset < 0) then begin
      nBytes := (nhdr.bitpix div 8);
      for i := 1 to 7 do begin
          if nhdr.dim[i] > 0 then
              nBytes := nBytes * nhdr.dim[i];
      end;
      nhdr.vox_offset := FSize(fname) - nBytes;
      if (nhdr.vox_offset < 0) then nhdr.vox_offset := -1;
  end;
  result := true;
end;//MHA
//{$DEFINE DECOMPRESSGZ}
{$IFDEF DECOMPRESSGZ}
function readMIF(var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian, isDimPermute2341: boolean): boolean;
//https://github.com/MRtrix3/mrtrix3/blob/master/matlab/read_mrtrix.m
//https://mrtrix.readthedocs.io/en/latest/getting_started/image_data.html
//https://mrtrix.readthedocs.io/en/latest/getting_started/image_data.html#the-image-transfom
//https://github.com/MRtrix3/mrtrix3/blob/52a2540d7d3158ec74d762ad5dd387777569f325/core/file/nifti1_utils.cpp
label
  666;
{$IFDEF GZIP}
const
  kGzSz=65536;
{$ENDIF}
var
  FP: TextFile;
  str, key, vals, fstr: string;
  mArray: TStringList;
  nTransforms, nItems, i, j, k, nDim : integer;
  repetitionTime: single;
  layout: array [1..7] of double;
  pixdim: array [1..7] of single;
  dim: array [1..7] of integer;
  m: Mat44;
  m33: mat33;
  originVox, originMM: vect3;
  {$IFDEF GZIP}
  //the GZ MIF header is trouble: unlike NIfTI it is variable size, unlike NRRD it is part of the compressed stream
  // here the kludge is to extract the ENTIRE image to disk in order to read the header.
  // optimal would be to read a memory stream and detect '\nEND\n' when decompressing...
  // however, this format is discouraged so for the moment this seems sufficient
  fnameGZ: string = '';
  zStream: TGZFileStream;
  dStream: TFileStream;
  bytes : array of byte;
  bytescopied: integer;
  {$ENDIF}
begin
  str := UpCaseExt(fname);
  if str = '.GZ' then begin
     fstr := fname;
     {$IFDEF GZIP}
     fname := changefileext(fstr,'');
     if not fileexists(fname) then begin
        fnameGZ := fstr;
        zStream := TGZFileStream.Create(fstr,gzOpenRead);
        dStream := TFileStream.Create(fname,fmOpenWrite or fmCreate );
        setlength(bytes, kGzSz);
        repeat
              bytescopied := zStream.read(bytes[0],kGzSz);
              dStream.Write(bytes[0],bytescopied) ;
        until bytescopied < kGzSz;
        dStream.Free;
        zStream.Free;
     end;
     {$ELSE}
     showmessage('Unable to decompress .MIF.GZ');
     exit;
     {$ENDIF}
  end;
  swapEndian :=false;
  result := false;
  for i := 1 to 7 do begin
      layout[i] := i;
      dim[i] := 1;
      pixdim[i] := 1.0;
  end;
  repetitionTime := 0.0;
  LOAD_MAT44(m,1,0,0,0, 0,1,0,0, 0,0,1,0);
  nTransforms := 0;
  FileMode := fmOpenRead;
  AssignFile(fp,fname);
  reset(fp);
  mArray := TStringList.Create;
  if EOF(fp) then goto 666;
  readln(fp,str);
  if str <> 'mrtrix image' then goto 666;
  while (not EOF(fp))  do begin
    readln(fp,str);
    if str = 'END' then break;
    splitstrStrict(':',str,mArray);
    if mArray.count < 2 then continue;
    key := mArray[0]; //e.g. "dim: 1,2,3" -> "dim"
    vals := mArray[1]; //e.g. "dim: 1,2,3" -> "1,2,3"
    splitstrStrict(',',vals,mArray);
    nItems := mArray.count;
    mArray[0] := Trim(mArray[0]);  //" Float32LE" -> "Float32LE"
    //str := mArray[0];
    //mArray.Delete(i);
    if (ansipos('RepetitionTime', key) = 1) and (nItems > 0)  then begin
      repetitionTime := strtofloatdef(mArray[0], 0);
      continue;
    end;
    if (ansipos('layout', key) = 1) and (nItems > 1) and (nItems < 7) then begin
      for i := 1 to nItems do begin
          layout[i] := strtofloatdef(mArray[i-1],i);
          if (mArray[i-1][1] = '-') and (layout[i] >= 0) then
             layout[i] := -0.00001;
      end;
      continue;
    end;
    if (ansipos('transform', key) = 1) and (nItems > 1) and (nItems < 5) and (nTransforms < 3) then begin
      for i := 0 to (nItems-1) do
          m[nTransforms,i] := strtofloatdef(mArray[i],i);
      nTransforms := nTransforms + 1;
      continue;
    end;
    if (ansipos('dim', key) = 1) and (nItems > 1) and (nItems < 7) then begin
      nDim := nItems;
      for i := 1 to nItems do
           dim[i] := strtointdef(mArray[i-1],0);
       continue;
    end;
    if (ansipos('scaling', key) = 1) and (nItems > 1) and (nItems < 7) then begin
        nhdr.scl_inter := strtofloatdef(mArray[0],0);
        nhdr.scl_slope := strtofloatdef(mArray[1],1);
    end;
    if (ansipos('vox', key) = 1) and (nItems > 1) and (nItems < 7) then begin
       //NSLog('BINGO'+mArray[0]);
       for i := 1 to nItems do
           pixdim[i] := strtofloatdef(mArray[i-1],0);
           //nhdr.pixdim[i] := strtofloatdef(mArray[i-1],0);
       continue;
    end;
    if (ansipos('datatype', key) = 1) and (nItems > 0) then begin
      if (ansipos('Int8', mArray[0]) = 1) then
         nhdr.datatype := kDT_INT8
      else if (ansipos('UInt8', mArray[0]) = 1) then
         nhdr.datatype := kDT_UINT8
      else if (ansipos('UInt16', mArray[0]) = 1) then
            nhdr.datatype := kDT_UINT16
      else if (ansipos('Int16', mArray[0]) = 1) then
        nhdr.datatype := kDT_INT16
      else if (ansipos('Float32', mArray[0]) = 1) then
         nhdr.datatype := kDT_FLOAT32
      else
         NSLog('unknown datatype '+mArray[0]+' '+inttostr(ansipos('Float32LX', mArray[0])));
      {$IFDEF ENDIAN_BIG}
      if (ansipos('LE', mArray[0]) > 0) then
         swapEndian :=true;
      {$ELSE}
      if (ansipos('BE', mArray[0]) > 0) then
         swapEndian :=true;
      {$ENDIF}
      continue;

    end;
    if (ansipos('file', key) = 1) and (nItems > 0) then begin
       fstr := trim(copy(str,pos(':',str)+1, maxint)); //get full string, e.g. "file: with spaces.dat"
       splitstrStrict(' ',mArray[0],mArray);
       nItems :=mArray.count;
       if (nItems > 1) and (mArray[0] = '.') then
          nhdr.vox_offset := strtointdef(mArray[1],0) //"file: . 328" -> 328 *)
       else begin
           if not fileexists(fstr) then //e.g. "out.dat" -> "\mydir\out.dat"
              fname := ExtractFilePath(fname) + fstr
           else
               fname := fstr;
       end;
       continue;
    end;
    //NSLog(format('%d "%s" %d',[ansipos('file', key) , key, nItems]));
  end;
  //https://github.com/MRtrix3/mrtrix3/blob/52a2540d7d3158ec74d762ad5dd387777569f325/core/file/nifti_utils.cpp
  // transform_type adjust_transform (const Header& H, vector<size_t>& axes)
  for i := 0 to 2 do
      originVox[0] := 0;
  if nDim < 2 then goto 666;
  nhdr.dim[0] := nDim;
  LOAD_MAT33(m33,1,0,0, 0,1,0, 0,0,1);
  for i := 1 to nDim do begin
      j := abs(round(layout[i]))+1;
      nhdr.dim[j] := dim[i];
      if specialsingle(pixdim[i]) then
         pixdim[i] := 0.0;
      nhdr.pixdim[j] := pixdim[i];
      if j = 4 then
         nhdr.pixdim[j] := repetitionTime;
      if i > 3 then continue;
      //for k := 0 to 2 do
      //    m33[k, j-1] :=  m[i-1,k];
      //for k := 0 to 2 do
      //    m33[i-1, k] :=  m[i-1,k];
      for k := 0 to 2 do
          m33[k,j-1] :=  m[k,i-1];

      //rot33[j-1,i-1] := nhdr.pixdim[j];
      if layout[i] < 0 then begin
         nhdr.pixdim[j] := -pixdim[i];
         originVox[j-1] := dim[i]-1;
      end;
  end;
  //scale matrix
  for i := 0 to 2 do
      for j := 0 to 2 do
          m33[j,i] := m33[j,i] * nhdr.pixdim[i+1];
  originMM := nifti_mat33vec_mul(m33, originVox);
  for i := 1 to 3 do
      nhdr.pixdim[i] := abs(nhdr.pixdim[i]);
  for i := 0 to 2 do
    m[i,3] := m[i,3] - originMM[i];
  (*
  str := format('%g %g %g', [pixdim[1], pixdim[2], pixdim[3]]);
  str := format('m = [%g %g %g; %g %g %g; %g %g %g]',[
        m33[0,0], m33[0,1], m33[0,2],
        m33[1,0], m33[1,1], m33[1,2],
        m33[2,0], m33[2,1], m33[2,2]]);
  str := format('%g %g %g', [originVox[0], originVox[1], originVox[2]]);
  str := format('v = [%g %g %g]', [originMM[0], originMM[1], originMM[2]]);
  Clipboard.AsText := str; *)

    nhdr.srow_x[0] := m33[0,0];
    nhdr.srow_x[1] := m33[0,1];
    nhdr.srow_x[2] := m33[0,2];
    nhdr.srow_x[3] :=   m[0,3];
    nhdr.srow_y[0] := m33[1,0];
    nhdr.srow_y[1] := m33[1,1];
    nhdr.srow_y[2] := m33[1,2];
    nhdr.srow_y[3] :=   m[1,3];
    nhdr.srow_z[0] := m33[2,0];
    nhdr.srow_z[1] := m33[2,1];
    nhdr.srow_z[2] := m33[2,2];
    nhdr.srow_z[3] :=   m[2,3];
  (*str := (format('m = [%g %g %g %g; %g %g %g %g; %g %g %g %g; 0 0 0 1]',[
    nhdr.srow_x[0], nhdr.srow_x[1], nhdr.srow_x[2], nhdr.srow_x[3],
    nhdr.srow_y[0], nhdr.srow_y[1], nhdr.srow_y[2], nhdr.srow_y[3],
    nhdr.srow_z[0], nhdr.srow_z[1], nhdr.srow_z[2], nhdr.srow_z[3]]));
  Clipboard.AsText := str; *)
  convertForeignToNifti(nhdr);
  result := true;
666:
    CloseFile(FP);
    Filemode := 2;
    {$IFDEF GZIP}
    if (fnameGZ <> '') and (fileexists(fnameGZ)) then begin
       deletefile(fname);
       fname := fnameGZ;
       gzBytes := K_gzBytes_headerAndImageCompressed;
    end;

    {$ENDIF}
    mArray.Free;
end; //readMIF()
{$ELSE}
function StreamNullStrRaw(Stream: TFileStream): string;
var
  b: byte;
begin
  result := '';
  while (Stream.Position < Stream.Size) do begin
        b := Stream.ReadByte;
        if b = $0A then exit;
        if b = $0D then continue;
        result := result + chr(b);
  end;
end;

(*function StreamNullStrGz(Stream: TGZFileStream): string;
var
  b: byte;
begin
  result := '';
  while (true) do begin
        b := Stream.ReadByte;
        if b = $0A then exit;
        if b = $00 then exit;
        if b = $0D then continue;
        result := result + chr(b);
  end;
end;*)

function StreamNullStrGz(Stream: TGZFileStream): string;
var
  n: integer;
  b: array [0..0] of byte;
begin
  result := '';
  b[0] := $0A;
  while (true) do begin
        n := Stream.read(b,1);
        if n < 1 then break;
        if b[0] = $0A then exit;
        if b[0] = $00 then exit;
        if b[0] = $0D then continue;
        result := result + chr(b[0]);
  end;
  if n < 1 then result := 'END';
end;


function readMIF(var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
//https://github.com/MRtrix3/mrtrix3/blob/master/matlab/read_mrtrix.m
//https://mrtrix.readthedocs.io/en/latest/getting_started/image_data.html
//https://mrtrix.readthedocs.io/en/latest/getting_started/image_data.html#the-image-transfom
//https://github.com/MRtrix3/mrtrix3/blob/52a2540d7d3158ec74d762ad5dd387777569f325/core/file/nifti1_utils.cpp
label
  666;
var
  str, key, vals, fstr: string;
  mArray: TStringList;
  nTransforms, nItems, i, j, k, nDim : integer;
  repetitionTime: single;
  layout: array [1..7] of double;
  pixdim: array [1..7] of single;
  dim: array [1..7] of integer;
  m: Mat44;
  m33: mat33;
  originVox, originMM: vect3;
  fs: TFileStream;
  {$IFDEF GZIP}
  zfs: TGZFileStream;
  isGz: boolean = false;
  {$ENDIF}
begin
  str := UpCaseExt(fname);
  if str = '.GZ' then begin
     {$IFDEF GZIP}
     isGz := true;
     zfs := TGZFileStream.Create(fname,gzOpenRead);
     {$ELSE}
     showmessage('Unable to decompress .MIF.GZ');
     exit;
     {$ENDIF}
  end;
  swapEndian :=false;
  result := false;
  for i := 1 to 7 do begin
      layout[i] := i;
      dim[i] := 1;
      pixdim[i] := 1.0;
  end;
  repetitionTime := 0.0;
  LOAD_MAT44(m,1,0,0,0, 0,1,0,0, 0,0,1,0);
  nTransforms := 0;
  mArray := TStringList.Create;
  if isGz then
     str := StreamNullStrGz(zfs)
  else begin
       fs := TFileStream.Create(fname, fmOpenRead);
       str := StreamNullStrRaw(fs);
  end;
  if str <> 'mrtrix image' then goto 666;
  while (isGz ) or ((not isGz) and (fs.position < fs.Size))  do begin
    if isGz then
       str := StreamNullStrGz(zfs)
    else
        str := StreamNullStrRaw(fs);
    if str = 'END' then break;
    splitstrStrict(':',str,mArray);
    if mArray.count < 2 then continue;
    key := mArray[0]; //e.g. "dim: 1,2,3" -> "dim"
    vals := mArray[1]; //e.g. "dim: 1,2,3" -> "1,2,3"
    splitstrStrict(',',vals,mArray);
    nItems := mArray.count;
    mArray[0] := Trim(mArray[0]);  //" Float32LE" -> "Float32LE"
    if (ansipos('RepetitionTime', key) = 1) and (nItems > 0)  then begin
      repetitionTime := strtofloatdef(mArray[0], 0);
      continue;
    end;
    if (ansipos('layout', key) = 1) and (nItems > 1) and (nItems < 7) then begin
      for i := 1 to nItems do begin
          layout[i] := strtofloatdef(mArray[i-1],i);
          if (mArray[i-1][1] = '-') and (layout[i] >= 0) then
             layout[i] := -0.00001;
          if (i <= 3) and (abs(layout[i]) >= 3) then begin
              showmessage('The first three strides are expected to be spatial (check for update).');
              goto 666;
          end;
      end;
      continue;
    end;
    if (ansipos('transform', key) = 1) and (nItems > 1) and (nItems < 5) and (nTransforms < 3) then begin
      for i := 0 to (nItems-1) do
          m[nTransforms,i] := strtofloatdef(mArray[i],i);
      nTransforms := nTransforms + 1;
      continue;
    end;
    if (ansipos('dim', key) = 1) and (nItems > 1) and (nItems < 7) then begin
      nDim := nItems;
      for i := 1 to nItems do
           dim[i] := strtointdef(mArray[i-1],0);
       continue;
    end;
    if (ansipos('scaling', key) = 1) and (nItems > 1) and (nItems < 7) then begin
        nhdr.scl_inter := strtofloatdef(mArray[0],0);
        nhdr.scl_slope := strtofloatdef(mArray[1],1);
    end;
    if (ansipos('vox', key) = 1) and (nItems > 1) and (nItems < 7) then begin
       //NSLog('BINGO'+mArray[0]);
       for i := 1 to nItems do
           pixdim[i] := strtofloatdef(mArray[i-1],0);
           //nhdr.pixdim[i] := strtofloatdef(mArray[i-1],0);
       continue;
    end;
    if (ansipos('datatype', key) = 1) and (nItems > 0) then begin
      if (ansipos('Int8', mArray[0]) = 1) then
         nhdr.datatype := kDT_INT8
      else if (ansipos('UInt8', mArray[0]) = 1) then
         nhdr.datatype := kDT_UINT8
      else if (ansipos('UInt16', mArray[0]) = 1) then
            nhdr.datatype := kDT_UINT16
      else if (ansipos('Int16', mArray[0]) = 1) then
        nhdr.datatype := kDT_INT16
      else if (ansipos('Float32', mArray[0]) = 1) then
         nhdr.datatype := kDT_FLOAT32
      else
         NSLog('unknown datatype '+mArray[0]);
      {$IFDEF ENDIAN_BIG}
      if (ansipos('LE', mArray[0]) > 0) then
         swapEndian :=true;
      {$ELSE}
      if (ansipos('BE', mArray[0]) > 0) then
         swapEndian :=true;
      {$ENDIF}
      continue;
    end;
    if (ansipos('file', key) = 1) and (nItems > 0) then begin
       fstr := trim(copy(str,pos(':',str)+1, maxint)); //get full string, e.g. "file: with spaces.dat"
       splitstrStrict(' ',mArray[0],mArray);
       nItems :=mArray.count;
       if (nItems > 1) and (mArray[0] = '.') then
          nhdr.vox_offset := strtointdef(mArray[1],0) //"file: . 328" -> 328
       else begin
           if not fileexists(fstr) then //e.g. "out.dat" -> "\mydir\out.dat"
              fname := ExtractFilePath(fname) + fstr
           else
               fname := fstr;
       end;
       continue;
    end;
  end;
  //https://github.com/MRtrix3/mrtrix3/blob/52a2540d7d3158ec74d762ad5dd387777569f325/core/file/nifti_utils.cpp
  // transform_type adjust_transform (const Header& H, vector<size_t>& axes)
  for i := 0 to 2 do
      originVox[0] := 0;
  if nDim < 2 then goto 666;
  nhdr.dim[0] := nDim;
  LOAD_MAT33(m33,1,0,0, 0,1,0, 0,0,1);
  for i := 1 to nDim do begin
      j := abs(round(layout[i]))+1;
      nhdr.dim[j] := dim[i];
      if specialsingle(pixdim[i]) then
         pixdim[i] := 0.0;
      nhdr.pixdim[j] := pixdim[i];
      if j = 4 then
         nhdr.pixdim[j] := repetitionTime;
      if i > 3 then continue;
      for k := 0 to 2 do
          m33[k,j-1] :=  m[k,i-1];
      if layout[i] < 0 then begin
         nhdr.pixdim[j] := -pixdim[i];
         originVox[j-1] := dim[i]-1;
      end;
  end;
  //scale matrix
  for i := 0 to 2 do
      for j := 0 to 2 do
          m33[j,i] := m33[j,i] * nhdr.pixdim[i+1];
  originMM := nifti_mat33vec_mul(m33, originVox);
  for i := 1 to 3 do
      nhdr.pixdim[i] := abs(nhdr.pixdim[i]);
  for i := 0 to 2 do
    m[i,3] := m[i,3] - originMM[i];
    nhdr.srow_x[0] := m33[0,0];
    nhdr.srow_x[1] := m33[0,1];
    nhdr.srow_x[2] := m33[0,2];
    nhdr.srow_x[3] :=   m[0,3];
    nhdr.srow_y[0] := m33[1,0];
    nhdr.srow_y[1] := m33[1,1];
    nhdr.srow_y[2] := m33[1,2];
    nhdr.srow_y[3] :=   m[1,3];
    nhdr.srow_z[0] := m33[2,0];
    nhdr.srow_z[1] := m33[2,1];
    nhdr.srow_z[2] := m33[2,2];
    nhdr.srow_z[3] :=   m[2,3];
  convertForeignToNifti(nhdr);
  result := true;
666:
    if isGz then begin
       gzBytes := K_gzBytes_headerAndImageCompressed;
       zfs.Free;
    end else
        fs.Free;
    mArray.Free;
end; //readMIF()
{$ENDIF}

function readICSHeader(var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
label
	666;
var
  isInt: boolean = true;
  isSigned: boolean = true;
  f: TFByte;
  str: string;
  i,nItems, lsb, bpp: integer;
  mArray: TStringList;
   //https://onlinelibrary.wiley.com/doi/epdf/10.1002/cyto.990110502
begin
  lsb := 0;
  bpp := 0;
  gzBytes := 0;
  result := false;
  mArray := TStringList.Create;
  AssignFile(f, fname);
  FileMode := fmOpenRead;
  Reset(f,1);
  ReadLnBin(f, str); //first line 011 012
  if (length(str) < 1) or (str[1] <> chr($09)) then
  	goto 666; //not a valid ICS file
  ReadLnBin(f, str); //version
  if not AnsiStartsText('ics_version', str) then
  	goto 666;
  ReadLnBin(f, str); //filename
  if not AnsiStartsText('filename', str) then begin
 	{$IFDEF UNIX} writeln('Error: expected ICS tag "filename": ICS 2.0?');{$ENDIF}
  	goto 666;
  end;
  splitstr(' ',str,mArray);
  nItems :=mArray.count;
  if (nItems < 2) then goto 666;
  str := fname;
  fname := extractfilename(mArray[1]);
  if upcase(extractfileext(fname)) <> '.IDS' then
  	fname := fname+'.ids';
  (*if (not fileexists(fname)) and fileexists(fname+ '.Z') then begin
     gzBytes := K_gzBytes_onlyImageCompressed;//K_gzBytes_headerAndImageCompressed;
     fname := fname+'.Z';
     //example testim_c.ids.Z has no Zlib header or footer
  end; *)
  if not fileexists(fname) then begin
  	fname := ExtractFilePath(str)+fname;
      (*if (not fileexists(fname)) and fileexists(fname+ '.Z') then begin
         gzBytes := K_gzBytes_onlyImageCompressed;//K_gzBytes_headerAndImageCompressed;
         fname := fname+'.Z';
      end;*)
        if not fileexists(fname) then begin
  	   NSLog('Unable to find IDS image '+fname);
  	   goto 666;
  	end;
  end;
  while ReadLnBin(f, str) do begin
  	splitstr(' ',str,mArray);
  	nItems :=mArray.count;
        //showmessage(str);
  	if (nItems > 4) and AnsiStartsText('layout', mArray[0]) and AnsiStartsText('sizes', mArray[1]) then begin
  		//writeln('!bpp', mArray[2]);
                bpp := StrToIntDef(mArray[2],0);
                //showmessage(str);
                for i := 3 to (nItems-1) do
                    nhdr.dim[i-2] := StrToIntDef(mArray[i],0);
  		//layout	sizes	8	256	256
  	end;
  	if (nItems > 3) and AnsiStartsText('parameter', mArray[0]) and AnsiStartsText('scale', mArray[1]) then begin
           for i := 2 to (nItems-1) do
               nhdr.pixdim[i-1] := StrToIntDef(mArray[i],0);
  	end;
  	if (nItems > 2) and AnsiStartsText('representation', mArray[0]) and AnsiStartsText('compression', mArray[1]) then begin
  		if not AnsiStartsText('uncompressed', mArray[2]) then begin
  			{$IFDEF UNIX} writeln('Unknown compression '+str);{$ENDIF}
  			goto 666;
  		end;
  		writeln('!no compression', mArray[2]);
  		//layout	sizes	8	256	256
  	end;
  	if (nItems > 2) and AnsiStartsText('representation', mArray[0]) and AnsiStartsText('format', mArray[1]) then begin
  		if not AnsiStartsText('integer', mArray[2]) then
                   isInt := false;
  	end;
  	if (nItems > 2) and AnsiStartsText('representation', mArray[0]) and AnsiStartsText('sign', mArray[1]) then begin
  		if AnsiStartsText('unsigned', mArray[2]) then
                   isSigned := false;
  	end;
  	if (nItems > 2) and AnsiStartsText('representation', mArray[0]) and AnsiStartsText('byte_order', mArray[1]) then begin
  	   lsb := StrToIntDef(mArray[2],0);
  	end;
        //representation	byte_order	1
  	//writeln('-->'+str+'<<');
  end;
  if (bpp = 32) and (not isInt) then
     nhdr.datatype := kDT_FLOAT32
  else if (bpp = 32) and (isSigned) and (isInt) then
       nhdr.datatype := kDT_INT32
  else if (bpp = 32) and (not isSigned) and (isInt) then
       nhdr.datatype := kDT_UINT32
  else if (bpp = 16) and (isSigned) and (isInt) then
       nhdr.datatype := kDT_INT16
  else if (bpp = 16) and (not isSigned) and (isInt) then
       nhdr.datatype := kDT_UINT16
  else if (bpp = 8) and (isSigned) and (isInt) then
       nhdr.datatype := kDT_INT8
  else if (bpp = 8) and (not isSigned) and (isInt) then
       nhdr.datatype := kDT_UINT8
  else begin
       NSLog(format('Unsupported data type: bits %d signed %s int %s', [bpp, BoolToStr(isSigned,'T','F'), BoolToStr(isInt,'T','F')]));
       goto 666;
  end;
  nhdr.srow_x[0] := -nhdr.pixdim[1];
  nhdr.srow_x[1] := 0;
  nhdr.srow_x[2] := 0;
  nhdr.srow_x[3] := 0;

  nhdr.srow_y[0] := 0;
  nhdr.srow_y[1] := -nhdr.pixdim[2];
  nhdr.srow_y[2] := 0;
  nhdr.srow_y[3] := 0;

  nhdr.srow_z[0] := 0;
  nhdr.srow_z[1] := 0;
  nhdr.srow_z[2] := nhdr.pixdim[3];
  nhdr.srow_z[3] := 0;

  nhdr.vox_offset := 0;
  {$IFDEF ENDIAN_BIG}
  if (bpp > 8) and (lsb < 2) then
  {$ELSE}
  if (bpp > 8) and (lsb > 1) then
  {$ENDIF}
     swapEndian := true;
  convertForeignToNifti(nhdr);
  result := true;
  666:
  mArray.free;
  closefile(f);
end; //readICSHeader

function readNRRDHeader (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian, isDimPermute2341: boolean): boolean;
//http://www.sci.utah.edu/~gk/DTI-data/
//http://teem.sourceforge.net/nrrd/format.html
label
  666;
var
  FP: TextFile;
  ch: char;
  mArray: TStringList;
  pth, str,tagName,elementNames, str2: string;
  lineskip,byteskip,i,s,nItems,headerSize,matElements,fileposBytes: integer;
  mat: mat33;
  rot33: mat33;
  isOK, isDetachedFile,isFirstLine: boolean;
  offset: array[0..3] of single;
  vSqr, flt: single;
  transformMatrix: array [0..11] of single;
  dtMin, dtMax, dtRange, dtScale, oldRange, oldMin, oldMax: double;
begin
  oldMin := NaN;
  oldMax := NaN;
  //gX := gX + 1; GLForm1.caption := inttostr(gX);
  //LOAD_MAT33(rot33, 1,0,0, 0,1,0, 0,0,1);
  LOAD_MAT33(rot33, -1,0,0, 0,-1,0, 0,0,1);
  isDimPermute2341 := false;
  pth := ExtractFilePath(fname);
  isOK := true;
  {$IFDEF FPC}
  DefaultFormatSettings.DecimalSeparator := '.' ;
  //DecimalSeparator := '.';
  {$ELSE}
  DecimalSeparator := '.';
  {$ENDIF}
  result := false;
  gzBytes :=0;
  fileposBytes := 0;
  swapEndian :=false;
  //nDims := 0;
  headerSize :=0;
  lineskip := 0;
  byteskip := 0;
  isDetachedFile :=false;
  matElements :=0;
  mArray := TStringList.Create;
  isFirstLine := true;
  FileMode := fmOpenRead;
  AssignFile(fp,fname);
  reset(fp);
  while (not EOF(fp))  do begin
    str := '';
    while not EOF(fp) do begin
      read(fp,ch);
      if (ch = chr($00)) then break; //NRRD format specifies blank line before raw data, but some writers ignore this requirement, e.g. https://www.mathworks.com/matlabcentral/fileexchange/51174-dicom-medical-image-to-nrrd-medical-image
      fileposBytes := fileposBytes + 1;
      //if (ch = chr($0D)) or (ch = chr($0A)) then break;
      if (ch = chr($0D)) then continue;
      if (ch = chr($0A)) then break;

      str := str+ch;
    end;
    //showmessage('"'+str+'"');
    if str = '' then break; //if str = '' then continue;
    if (isFirstLine) then begin
      if (length(str) <4) or (str[1]<>'N') or (str[2]<>'R') or (str[3]<>'R') or (str[4]<>'D') then
        goto 666;
      isFirstLine := false;
    end;
    if (length(str) < 1) or (str[1]='#') then continue;
    splitstrStrict(':',str,mArray);
    if (mArray.count < 2) then continue;
    tagName := mArray[0];
    //showmessage(inttostr(length(tagName))+':'+tagName);
    elementNames := mArray[1];
    splitstr(',',elementNames,mArray);
    nItems :=mArray.count;
    if (nItems < 1) then continue;
    for i := 0 to (nItems-1) do
      mArray.Strings[i] := cleanStr(mArray.Strings[i]); //remove '(' and ')'
    (*if AnsiContainsText(tagName, 'dimension') then
      nDims := strtoint(mArray.Strings[0])
    else*) if AnsiStartsText( 'spacings', tagName) then begin
      if (nItems > 6) then nItems :=6;
      for i:=0 to (nItems-1) do
        nhdr.pixdim[i+1] :=strtofloat(mArray.Strings[i]);
    end else if (AnsiStartsText( 'oldmin', tagName)) or (AnsiStartsText( 'old min', tagName)) then begin
          oldMin :=strtofloat(mArray.Strings[i]);
    end else if (AnsiStartsText( 'oldmax', tagName)) or (AnsiStartsText( 'old max', tagName)) then begin
          oldMax :=strtofloat(mArray.Strings[i]);

    end else if AnsiStartsText('sizes', tagName) then begin
      if (nItems > 6) then nItems :=6;
      //for i:=1 to 6 do
      //    nhdr.dim[i] := 1;
      for i:=0 to (nItems-1) do
          nhdr.dim[i+1] := strtoint(mArray.Strings[i]);
    end else if AnsiStartsText('space directions',tagName) then begin
      if (nItems > 12) then nItems :=12;
      matElements := 0;
      for i:=0 to (nItems-1) do begin
        if (matElements = 0) and AnsiContainsText(mArray.Strings[i], 'none') then begin
           isDimPermute2341 := true;
        end;
          flt := strToFloatDef(mArray.Strings[i], kNANsingle);
          if not specialsingle(flt) then begin
             transformMatrix[matElements] :=strtofloat(mArray.Strings[i]);
             matElements := matElements + 1;
          end;
        end;
      if (matElements >= 12) then
          LOAD_MAT33(mat, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                     transformMatrix[4],transformMatrix[5],transformMatrix[6],
                     transformMatrix[8],transformMatrix[9],transformMatrix[10])
      else if (matElements >= 9) then
          LOAD_MAT33(mat, transformMatrix[0],transformMatrix[1],transformMatrix[2],
                     transformMatrix[3],transformMatrix[4],transformMatrix[5],
                     transformMatrix[6],transformMatrix[7],transformMatrix[8]);
    end else if AnsiStartsText('type', tagName) then begin //AnsiContainsText(tagName, 'type') then begin
      if AnsiContainsText(mArray.Strings[0], 'uchar') or
          AnsiContainsText(mArray.Strings[0], 'uint8') or
          AnsiContainsText(mArray.Strings[0], 'uint8_t')  then
          nhdr.datatype := KDT_UINT8 //DT_UINT8 DT_UNSIGNED_CHAR
      else if AnsiContainsText(mArray.Strings[0], 'short') or //specific so
               AnsiContainsText(mArray.Strings[0], 'int16') or
               AnsiContainsText(mArray.Strings[0], 'int16_t') then
          nhdr.datatype :=kDT_INT16 //DT_INT16
      else if AnsiContainsText(mArray.Strings[0], 'float') then
          nhdr.datatype := kDT_FLOAT32 //DT_FLOAT32
      else if AnsiContainsText(mArray.Strings[0], 'unsigned')
               and (nItems > 1) and AnsiContainsText(mArray.Strings[1], 'char') then
          nhdr.datatype := kDT_UINT8 //DT_UINT8
      else if AnsiContainsText(mArray.Strings[0], 'unsigned') and
               (nItems > 1) and AnsiContainsText(mArray.Strings[1], 'int') then
          nhdr.datatype := kDT_UINT32 //
      else if AnsiContainsText(mArray.Strings[0], 'signed') and
               (nItems > 1) and AnsiContainsText(mArray.Strings[1], 'char') then
          nhdr.datatype := kDT_INT8 //do UNSIGNED first, as "isigned" includes string "unsigned"
      else if AnsiContainsText(mArray.Strings[0], 'signed') and
               (nItems > 1) and AnsiContainsText(mArray.Strings[1], 'short') then
          nhdr.datatype := kDT_INT16 //do UNSIGNED first, as "isigned" includes string "unsigned"
      else if AnsiContainsText(mArray.Strings[0], 'double') then
          nhdr.datatype := kDT_DOUBLE //DT_DOUBLE
      else if AnsiContainsText(mArray.Strings[0], 'uint') then
          nhdr.datatype := kDT_UINT32
      else if AnsiContainsText(mArray.Strings[0], 'int') then //do this last and "uint" includes "int"
          nhdr.datatype := kDT_INT32
      else begin
          NSLog('Unsupported NRRD datatype'+mArray.Strings[0]);
          isOK := false;
          break;
      end
    end else if AnsiStartsText('endian', tagName) then begin
      {$IFDEF ENDIAN_BIG} //data always stored big endian
      if AnsiContainsText(mArray.Strings[0], 'little') then swapEndian :=true;
      {$ELSE}
      if AnsiContainsText(mArray.Strings[0], 'big') then swapEndian :=true;
      {$ENDIF}
    end else if AnsiStartsText('encoding',tagName) then begin
      if AnsiContainsText(mArray.Strings[0], 'raw') then
          gzBytes :=0
      else if AnsiContainsText(mArray.Strings[0], 'gz') or AnsiContainsText(mArray.Strings[0], 'gzip') then
          gzBytes := K_gzBytes_headerAndImageCompressed//K_gzBytes_headeruncompressed
      else begin
          NSLog('Unknown encoding format '+mArray.Strings[0]);
          isOK := false;
          break;
      end;
    end else if (AnsiStartsText('lineskip',tagName) or AnsiContainsText(tagName, 'line skip')) then begin //http://teem.sourceforge.net/nrrd/format.html#lineskip
      lineskip := strtointdef(mArray.Strings[0],0);
    end else if (AnsiStartsText('byteskip', tagName) or AnsiContainsText(tagName, 'byte skip')) then begin //http://teem.sourceforge.net/nrrd/format.html#byteskip
      byteskip := strtointdef(mArray.Strings[0],0);
    end else if AnsiStartsText('space origin', tagName) then begin
      if (nItems > 3) then nItems :=3;
      for i:=0 to (nItems-1) do
          offset[i] := strtofloat(mArray.Strings[i]);
    end else if (nItems > 0) and AnsiStartsText('space', tagName) then begin //must do this after "space origin" check
      if AnsiStartsText('right-anterior-superior', mArray.Strings[0]) or AnsiStartsText('RAS', mArray.Strings[0]) then
        LOAD_MAT33(rot33, 1,0,0, 0,1,0, 0,0,1); //native NIfTI, default identity transform
      if AnsiStartsText('left-anterior-superior', mArray.Strings[0]) or AnsiStartsText('LAS', mArray.Strings[0]) then
        LOAD_MAT33(rot33, -1,0,0, 0,1,0, 0,0,1); //left-right swap relative to NIfTI
      if AnsiStartsText('left-posterior-superior', mArray.Strings[0]) or AnsiStartsText('LPS', mArray.Strings[0]) then begin//native NIfTI, default identity transform
         LOAD_MAT33(rot33, -1,0,0, 0,-1,0, 0,0,1); //left-right and anterior-posterior swap relative to NIfTI
      end;
    end else if AnsiStartsText('data file',tagName) or AnsiContainsText(tagName, 'datafile') then begin
      str2 := str;
      str := mArray.Strings[0];
      if (pos('LIST', UpperCase(str)) = 1) and (length(str) = 4) then begin  //e.g. "data file: LIST"
         readln(fp,str);
      end;
      if (pos('%', UpperCase(str)) > 0) and (nItems  > 1) then begin  //e.g. "data file: ./r_sphere_%02d.raw.gz 1 4 1"
         str := format(str,[strtoint(mArray.Strings[1])]);
      end;
      if fileexists(str) then
        fname := str
      else begin
         if (length(str) > 0) and (str[1] = '.') then  // "./r_sphere_01.raw.gz"
           str := copy(str, 2, length(str)-1 );
         if (length(str) > 0) and (str[1] = pathdelim) then  // "./r_sphere_01.raw.gz"
           str := copy(str, 2, length(str)-1 );  // "/r_sphere_01.raw.gz"
        fname := ExtractFilePath(fname)+str;
      end;
      if not fileexists(fname) then begin
          str2 := trim(copy(str2,pos(':',str2)+1, maxint));
          fname := str2;
          if not fileexists(fname) then
            fname := pth + str2;
          //showmessage(inttostr(nhdr.datatype));
      end;
      isDetachedFile :=true;
      //break;

    end; //for ...else tag names
  end;
  if (nhdr.datatype <> kDT_FLOAT32) and (nhdr.datatype <> kDT_DOUBLE) and (not specialdouble(oldMin)) and (not specialdouble(oldMax)) then begin
     oldRange := oldMax - oldMin;
     dtMin := 0; //DT_UINT8, DT_RGB24, DT_UINT16
     if (nhdr.datatype = kDT_INT16) then dtMin := -32768.0;
     if (nhdr.datatype = kDT_INT32) then dtMin := -2147483648;
     dtMax := 255.00; //DT_UINT8, DT_RGB24
     if (nhdr.datatype = kDT_INT16) then dtMax := 32767;
     if (nhdr.datatype = kDT_UINT16) then dtMax := 65535.0;
     if (nhdr.datatype = kDT_INT32) then dtMax := 2147483647.0;
     dtRange := dtMax - dtMin;
     dtScale := oldRange/dtRange;
     nhdr.scl_slope := dtScale;
     nhdr.scl_inter := (dtMin*dtScale)- oldMin;
     //showmessage(format('%g..%g', [oldMin,oldMax]));
  end;
  if ((headerSize = 0) and ( not isDetachedFile)) then begin
    if gzBytes = K_gzBytes_headerAndImageCompressed then
      gzBytes := K_gzBytes_onlyImageCompressed; //raw text file followed by GZ image
    if lineskip > 0 then begin
      for i := 1 to lineskip do begin
        while not EOF(fp) do begin
              read(fp,ch);
              fileposBytes := fileposBytes + 1;
              if (ch = chr($0D)) or (ch = chr($0A)) then break;
        end; //for each character in line
      end; //for each line
    end; //if lineskip
    headerSize :=fileposBytes;
      end;
  result := true;
  if (lineskip > 0) and (isDetachedFile) then begin
     NSLog('Unsupported NRRD feature: lineskip in detached file');
     result := false;
  end;
  if (byteskip > 0) then begin
    headerSize := headerSize + byteskip;
    //NSLog('Unsupported NRRD feature: byteskip');
    //result := false;
  end;
  if not isOK then result := false;
  //GLForm1.ShaderMemo.Lines.Add(format(' %d', [gzBytes]));
666:
  CloseFile(FP);
  Filemode := 2;
  mArray.free;
  if not result then exit;
  nhdr.vox_offset :=headerSize;
  if (matElements >= 9) then begin
      //mat := nifti_mat33_mul( mat , rot33);
      if rot33[0,0] < 0 then offset[0] := -offset[0]; //origin L<->R
      if rot33[1,1] < 0 then offset[1] := -offset[1]; //origin A<->P
      if rot33[2,2] < 0 then offset[2] := -offset[2]; //origin S<->I
       mat := nifti_mat33_mul( mat , rot33);
        nhdr.srow_x[0] := mat[0,0];
        nhdr.srow_x[1] := mat[1,0];
        nhdr.srow_x[2] := mat[2,0];
        nhdr.srow_x[3] := offset[0];
        nhdr.srow_y[0] := mat[0,1];
        nhdr.srow_y[1] := mat[1,1];
        nhdr.srow_y[2] := mat[2,1];
        nhdr.srow_y[3] := offset[1];
        nhdr.srow_z[0] := mat[0,2];
        nhdr.srow_z[1] := mat[1,2];
        nhdr.srow_z[2] := mat[2,2];
        nhdr.srow_z[3] := offset[2];
      //end;
        //next: ITK does not generate a "spacings" tag - get this from the matrix...
        for s :=0 to 2 do begin
            vSqr :=0.0;
            for i :=0 to 2 do
                vSqr := vSqr+ ( mat[s,i]*mat[s,i]);
            nhdr.pixdim[s+1] :=sqrt(vSqr);
        end //for each dimension
  end;
  (*showmessage(format('m = [%g %g %g %g; %g %g %g %g; %g %g %g %g; 0 0 0 1]',[
    nhdr.srow_x[0], nhdr.srow_x[1], nhdr.srow_x[2], nhdr.srow_x[3],
    nhdr.srow_y[0], nhdr.srow_y[1], nhdr.srow_y[2], nhdr.srow_y[3],
    nhdr.srow_z[0], nhdr.srow_z[1], nhdr.srow_z[2], nhdr.srow_z[3]]));*)
  convertForeignToNifti(nhdr);
  //showmessage(floattostr(nhdr.vox_offset));
  //nhdr.vox_offset := 209;
end; //readNRRDHeader()

procedure THD_daxes_to_NIFTI (var nhdr: TNIFTIhdr; xyzDelta, xyzOrigin: vect3; orientSpecific: ivect3);
//see http://afni.nimh.nih.gov/pub/dist/src/thd_matdaxes.c
const
  ORIENT_xyz1 = 'xxyyzzg'; //note Pascal strings indexed from 1, not 0!
  //ORIENT_sign1 = '+--++-';  //note Pascal strings indexed from 1, not 0!
var
  //axnum: array[0..2] of integer;
  axcode: array[0..2] of char;
  //axsign: array[0..2] of char;
  axstart,axstep: array[0..2] of single;
  ii, nif_x_axnum, nif_y_axnum, nif_z_axnum: integer;
  qto_xyz: mat44;

begin
    nif_x_axnum := -1;
    nif_y_axnum := -1;
    nif_z_axnum := -1;
    //axnum[0] := nhdr.dim[1];
    //axnum[1] := nhdr.dim[2];
    //axnum[2] := nhdr.dim[3];
    axcode[0] := ORIENT_xyz1[1+ orientSpecific[0] ] ;
    axcode[1] := ORIENT_xyz1[1+ orientSpecific[1] ] ;
    axcode[2] := ORIENT_xyz1[1+ orientSpecific[2] ] ;
    //axsign[0] := ORIENT_sign1[1+ orientSpecific[0] ] ;
    //axsign[1] := ORIENT_sign1[1+ orientSpecific[1] ] ;
    //axsign[2] := ORIENT_sign1[1+ orientSpecific[2] ] ;
    axstep[0] := xyzDelta[0] ;
    axstep[1] := xyzDelta[1]  ;
    axstep[2] := xyzDelta[2]  ;
    axstart[0] := xyzOrigin[0] ;
    axstart[1] := xyzOrigin[1] ;
    axstart[2] := xyzOrigin[2] ;
    for ii := 0 to 2 do begin
        if (axcode[ii] = 'x') then
            nif_x_axnum := ii
        else if (axcode[ii] = 'y') then
            nif_y_axnum := ii
        else
          nif_z_axnum := ii ;
    end;
    if (nif_x_axnum < 0) or (nif_y_axnum < 0) or (nif_z_axnum < 0) then exit; //not assigned
    if (nif_x_axnum  = nif_y_axnum) or (nif_x_axnum  = nif_z_axnum) or (nif_y_axnum  = nif_z_axnum) then exit; //not assigned
    ZERO_MAT44(qto_xyz);
    //-- set voxel and time deltas and units --
    nhdr.pixdim[1] := abs ( axstep[0] ) ;
    nhdr.pixdim[2] := abs ( axstep[1] ) ;
    nhdr.pixdim[3] := abs ( axstep[2] ) ;
    qto_xyz[0,nif_x_axnum] := - axstep[nif_x_axnum];
    qto_xyz[1,nif_y_axnum] := - axstep[nif_y_axnum];
    qto_xyz[2,nif_z_axnum] :=   axstep[nif_z_axnum];
    nhdr.qoffset_x :=  -axstart[nif_x_axnum] ;
    nhdr.qoffset_y :=  -axstart[nif_y_axnum];
    nhdr.qoffset_z :=  axstart[nif_z_axnum];
    qto_xyz[0,3] := nhdr.qoffset_x ;
    qto_xyz[1,3] := nhdr.qoffset_y ;
    qto_xyz[2,3] := nhdr.qoffset_z ;
    //nifti_mat44_to_quatern( qto_xyz , nhdr.quatern_b, nhdr.quatern_c, nhdr.quatern_d,dumqx, dumqy, dumqz, dumdx, dumdy, dumdz,nhdr.pixdim[0]) ;
    //nhdr.qform_code := kNIFTI_XFORM_SCANNER_ANAT;
    nhdr.srow_x[0] :=qto_xyz[0,0]; nhdr.srow_x[1] :=qto_xyz[0,1]; nhdr.srow_x[2] :=qto_xyz[0,2]; nhdr.srow_x[3] :=qto_xyz[0,3];
    nhdr.srow_y[0] :=qto_xyz[1,0]; nhdr.srow_y[1] :=qto_xyz[1,1]; nhdr.srow_y[2] :=qto_xyz[1,2]; nhdr.srow_y[3] :=qto_xyz[1,3];
    nhdr.srow_z[0] :=qto_xyz[2,0]; nhdr.srow_z[1] :=qto_xyz[2,1]; nhdr.srow_z[2] :=qto_xyz[2,2]; nhdr.srow_z[3] :=qto_xyz[2,3];
    nhdr.sform_code := kNIFTI_XFORM_SCANNER_ANAT;
end;

function readAFNIHeader (var fname: string; var nhdr: TNIFTIhdr; var gzBytes: int64; var swapEndian: boolean): boolean;
label
  666;
var
  sl, mArray: TStringList;
  typeStr,nameStr, valStr: string;
  lineNum, itemCount,i, vInt, nVols: integer;
  isAllVolumesSame, isProbMap, isStringAttribute: boolean;
  valArray  : Array of double;
  orientSpecific: ivect3;
  xyzOrigin, xyzDelta: vect3;
begin
 {$IFDEF FPC}
  DefaultFormatSettings.DecimalSeparator := '.' ;
 //DecimalSeparator := '.';
  {$ELSE}
  DecimalSeparator := '.';
  {$ENDIF}
  nVols := 1;
  result := false;
  isProbMap := false;
  gzBytes := 0;
  swapEndian := false;
  sl := TStringList.Create;
  mArray := TStringList.Create;
  sl.LoadFromFile(fname);
  if(sl.count) < 4 then goto 666;
  lineNum := -1;
  repeat
    //read type string
    lineNum := lineNum + 1;
    if length(sl[lineNum]) < 1 then continue;
    splitstr('=',sl[lineNum],mArray);
    if mArray.Count < 2 then continue;
    if not AnsiContainsText(cleanStr(mArray[0]), 'type') then continue;
    typeStr := cleanStr(mArray[1]);
    isStringAttribute :=  AnsiContainsText(typeStr, 'string-attribute');
    //next: read name string
    lineNum := lineNum + 1;
    if (lineNum >= (sl.count-1)) then continue;
    splitstr('=',sl[lineNum],mArray);
    if mArray.Count < 2 then continue;
    if not AnsiContainsText(cleanStr(mArray[0]), 'name') then continue;
    nameStr := cleanStr(mArray[1]);
    //if AnsiContainsText(nameStr,'BYTEORDER_STRING') and isStringAttribute then showmessage('txt');
    //next: read count string
    lineNum := lineNum + 1;
    if (lineNum >= (sl.count-1)) then continue;
    splitstr('=',sl[lineNum],mArray);
    if mArray.Count < 2 then continue;
    if not AnsiContainsText(cleanStr(mArray[0]), 'count') then continue;
    itemCount := strtoint(cleanStr(mArray[1]));
    if itemCount < 1 then exit;
    //next read values
    lineNum := lineNum + 1;
    if (lineNum > (sl.count-1)) then continue;
    valStr := sl[lineNum];
    while ((lineNum+1) <= (sl.count-1)) and (length(sl[lineNum+1]) > 0) do begin
      lineNum := lineNum + 1;  //AFNI wraps some arrays across multiple lines
      valStr := valStr + ' '+ sl[lineNum];
    end;
    splitstr(' ',valStr,mArray);
    if (mArray.Count < itemCount) then itemCount := mArray.Count; // <- only if corrupt
    if itemCount < 1 then continue; // <- only if corrupt data
    if isStringAttribute then begin
        if AnsiContainsText(nameStr,'BYTEORDER_STRING') then begin
              {$IFDEF ENDIAN_BIG}
              if AnsiContainsText(mArray[0],'LSB_FIRST') then swapEndian := true;
              {$ELSE}
              if AnsiContainsText(mArray[0],'MSB_FIRST') then swapEndian := true;
              {$ENDIF}
        end
    end else begin //if numeric attributes...
      setlength(valArray,itemCount);
      for i := 0 to (itemCount-1) do
        valArray[i] := strtofloat(cleanStr(mArray[i]) );
      //next - harvest data from important names
      if AnsiContainsText(nameStr,'BRICK_TYPES') then begin
              vInt := round(valArray[0]);
              if (vInt = 0) then begin
                  nhdr.datatype := kDT_UINT8;
              end else if (vInt = 1) then begin
                  nhdr.datatype := kDT_INT16; //16 bit signed int
              end else if (vInt = 3) then begin
                  nhdr.datatype := kDT_FLOAT32;//32-bit float
              end else begin
                  NSLog('Unsupported BRICK_TYPES '+inttostr(vInt));
                  goto 666;
              end;
              if (itemCount > 1) then begin //check that all volumes are of the same datatype
                  nVols := itemCount;
                  isAllVolumesSame := true;
                  for i := 1 to (itemCount-1) do
                      if (valArray[0] <> valArray[i]) then isAllVolumesSame := false;
                  if (not isAllVolumesSame) then begin
                      NSLog('Unsupported BRICK_TYPES feature: datatype varies between sub-bricks');
                      goto 666;
                  end;
              end; //if acount > 0
              //NSLog('HEAD datatype is '+inttostr(nhdr.datatype) );
          end else if AnsiContainsText(nameStr,'BRICK_FLOAT_FACS') then begin
              nhdr.scl_slope := valArray[0];
              if (itemCount > 1) then begin //check that all volumes are of the same datatype
                  isAllVolumesSame := true;
                  for i := 1 to (itemCount-1) do
                      if (valArray[0] <> valArray[i]) then isAllVolumesSame := false;
                  if (not isAllVolumesSame) then begin
                      NSLog('Unsupported BRICK_FLOAT_FACS feature: intensity scale between sub-bricks');
                  end;
              end; //if acount > 0
          end else if AnsiContainsText(nameStr,'DATASET_DIMENSIONS') then begin
              if itemCount > 3 then itemCount := 3;
              for i := 0 to (itemCount-1) do
                  nhdr.dim[i+1] := round(valArray[i]);
          end else if AnsiContainsText(nameStr,'ORIENT_SPECIFIC') then begin
              if itemCount > 3 then itemCount := 3;
              for i := 0 to (itemCount-1) do
                  orientSpecific[i] := round(valArray[i]);;
              //NSLog(@"HEAD orient specific %d %d %d",orientSpecific.v[0],orientSpecific.v[1],orientSpecific.v[2]);
          end else if AnsiContainsText(nameStr,'ORIGIN') then begin
              if itemCount > 3 then itemCount := 3;
              for i := 0 to (itemCount-1) do
                  xyzOrigin[i] := valArray[i];
              //NSLog(@"HEAD origin %g %g %g",xyzOrigin.v[0],xyzOrigin.v[1],xyzOrigin.v[2]);
          end else if AnsiContainsText(nameStr,'ATLAS_PROB_MAP') then begin
              if (round(valArray[0]) = 1) then isProbMap := true;
          end else if AnsiContainsText(nameStr,'ATLAS_LABEL_TABLE') then begin
              nhdr.intent_code := kNIFTI_INTENT_LABEL;
          end else if AnsiContainsText(nameStr,'DELTA') then begin
              if itemCount > 3 then itemCount := 3;
              for i := 0 to (itemCount-1) do
                  xyzDelta[i] := valArray[i];
              //NSLog(@"HEAD delta %g %g %g",xyzDelta.v[0],xyzDelta.v[1],xyzDelta.v[2]);
          end else if AnsiContainsText(nameStr,'TAXIS_FLOATS') then begin
              if (itemCount > 1) then nhdr.pixdim[4] := valArray[1]; //second item is TR
          end;
      end;// if isStringAttribute else numeric inputs...
  until (lineNum >= (sl.count-1));
  result := true;
666:
  valArray := nil; //release dynamic array
  Filemode := 2;
  sl.free;
  mArray.free;
  if not result then exit; //error - code jumped to 666 without setting result to true
  if (nVols > 1) then nhdr.dim[4] := nVols;
  if (isProbMap) and (nhdr.intent_code = kNIFTI_INTENT_LABEL)  then nhdr.intent_code := kNIFTI_INTENT_NONE;
  THD_daxes_to_NIFTI(nhdr, xyzDelta, xyzOrigin, orientSpecific );
  nhdr.vox_offset := 0;
  convertForeignToNifti(nhdr);
  fname := ChangeFileExt(fname, '.BRIK');
  if (not FileExists(fname)) then begin
    fname := fname+'.gz';
    gzBytes := K_gzBytes_headerAndImageCompressed;
  end;
end;

function readForeignHeader (var lFilename: string; var lHdr: TNIFTIhdr; var gzBytes: int64; var swapEndian, isDimPermute2341: boolean): boolean;
var
  lExt, lExt2GZ: string;
begin
  NII_Clear (lHdr);
  swapEndian := false;
  //gzBytes := false;
  isDimPermute2341 := false;
  result := false;
  if FSize(lFilename) < 140 then
      exit;
  lExt := UpCaseExt(lFilename);
  lExt2GZ := '';
  if (lExt = '.GZ') then begin
     lExt2GZ := changefileext(lFilename,'');
     lExt2GZ := UpCaseExt(lExt2GZ);
  end;
  if (lExt = '.DV') then
     result := nii_readDeltaVision(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.V') then
       result := nii_readEcat(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.VMR') then
       result := nii_readVmr(lFilename, false, lHdr, gzBytes, swapEndian)
  else if (lExt = '.V16') then
       result := nii_readVmr(lFilename, true, lHdr, gzBytes, swapEndian)
  else if (lExt = '.BVOX') then
       result := nii_readBVox(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.GIPL') then
       result := nii_readGipl(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.PIC') then
    result := nii_readpic(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.VTK') then
    result := readVTKHeader(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.MGH') or (lExt = '.MGZ') then
    result := readMGHHeader(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.MHD') or (lExt = '.MHA') then
    result := readMHAHeader(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.ICS') then
    result := readICSHeader(lFilename, lHdr, gzBytes, swapEndian)
  else if ((lExt2GZ = '.MIF') or (lExt = '.MIF') or (lExt = '.MIH')) then
       result := readMIF(lFilename, lHdr, gzBytes, swapEndian)
  else if (lExt = '.NRRD') or (lExt = '.NHDR') then
       result := readNRRDHeader(lFilename, lHdr, gzBytes, swapEndian, isDimPermute2341)
  else if (lExt = '.HEAD') then
    result := readAFNIHeader(lFilename, lHdr, gzBytes, swapEndian);
  if (not result) and (isTIFF(lFilename)) then
    NSLog('Use the Import menu (or ImageJ/Fiji) to convert TIFF and LSM files to NIfTI (or NRRD) for viewing')
  else if (not result) then begin
       lExt2GZ := isBioFormats(lFilename);
       if lExt2GZ <> '' then
          NSLog('Use ImageJ/Fiji to convert this '+lExt2GZ+' BioFormat image to NRRD for viewing');
  end;
  //GLForm1.IntensityBox.Caption := (format('%g', [lHdr.vox_offset]));
end;

end.

