unit glclrbar;
//openGL color bars
{$IFDEF FPC}
{$Include opts.inc}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
   {$IFDEF FPC}
    {$IFDEF COREGL}glcorearb,  gl_core_matrix,  {$ELSE}gl, glext, {$ENDIF}
    OpenGLContext,
  {$ELSE}
    dglOpenGL, glpanel, windows,pngimage,
  {$ENDIF}
  shaderu, texture2raycast, define_types,
  raycast_common, glmtext,Classes, SysUtils, Graphics,  math, dialogs;


const
  kMaxClrBar = 32;
type
 TLUTminmax = packed record
   LUT : TLUT;
   mn,mx: single;
 end;
  TGLClrbar = class
  private
         {$IFDEF COREGL}
         uniform_mtx: GLint;
         vbo_face2d, vao_point2d, shaderProgram: GLuint;
         {$ELSE}displayLst: GLuint;{$ENDIF}
         LUTs: array [1..kMaxClrBar] of TLUTminmax;
         nLUTs, scrnW, scrnH: integer;
         SizeFrac, MaxTotalSizeFrac, fForcedSizeFracX : Single;// = taLeftJustify;
         FontClr,BackClr: TGLRGBQuad;
         fisVertical, fisTopOrRight, isRedraw, isText: boolean;
         txt: TGLText;
         {$IFDEF COREGL}procedure CreateStrips;{$ENDIF}
         procedure CreateClrbar;
         procedure ScreenSize(nLUT,Width,Height: integer);
         procedure CreateTicksText(mn,mx: single; BarLength, BarTop, BarThick, fntScale: single);
         procedure SetVertical(isV: boolean);
         procedure SetTopOrRight(isTR: boolean);
         procedure SetBackColor(c: TGLRGBQuad);
         procedure SetFontColor(c: TGLRGBQuad);
         procedure SetForcedSizeFracX(f: single);
         procedure SetSizeFrac(f: single);

  public
    property ForcedSizeFracX: single read fForcedSizeFracX write SetForcedSizeFracX;
    property isVertical : boolean read fisVertical write SetVertical;
    property isTopOrRight : boolean read fisTopOrRight write SetTopOrRight;
    property BackColor : TGLRGBQuad read BackClr write SetBackColor;
    property FontColor : TGLRGBQuad read FontClr write SetFontColor;
    property SizeFraction : single read SizeFrac write SetSizeFrac;
    procedure Draw(nLUT, Width,Height, zoom,zoomOffsetX, zoomOffsetY: integer); //must be called while TOpenGLControl is current context
    procedure SetLUT(index: integer; LUT: TLUT; min,max: single);
    procedure ForceRedraw();
    {$IFDEF FPC}
    procedure ChangeFontName(fntname: string; Ctx: TOpenGLControl);
    constructor Create(fntname: string; Ctx: TOpenGLControl);
    {$ELSE}
    procedure ChangeFontName(fntname: string; Ctx: TGLPanel);
    constructor Create(fntname: string; Ctx: TGLPanel);
    {$ENDIF}
   Destructor  Destroy; override;
  end;
  //{$IFNDEF COREGL}var GLErrorStr : string = '';{$ENDIF}

implementation

{$IFDEF COREGL}
type
  TPoint3f = Packed Record
    x,y,z: single;
  end;

TVtxClr = Packed Record
  vtx   : TPoint3f; //vertex coordinates
  clr : TRGBA;
end;

var
    g2Dvnc: array of TVtxClr;
    g2Drgba : TRGBA;
    g2DNew: boolean;
    gnface: integer;

    const
        kBlockSz = 8192;
        kVert2D ='#version 330'
    +#10'layout(location = 0) in vec3 Vert;'
    +#10'layout(location = 3) in vec4 Clr;'
    +#10'out vec4 vClr;'
    +#10'uniform mat4 ModelViewProjectionMatrix;'
    +#10'void main() {'
    +#10'    gl_Position = ModelViewProjectionMatrix * vec4(Vert, 1.0);'
    +#10'    vClr = Clr;'
    +#10'}';
        kFrag2D = '#version 330'
    +#10'in vec4 vClr;'
    +#10'out vec4 color;'
    +#10'void main() {'
    +#10'    color = vClr;'
    +#10'}';

procedure TGLClrbar.CreateStrips;
const
    kATTRIB_VERT = 0;  //vertex XYZ are positions 0,1,2
    kATTRIB_CLR = 3;   //color RGBA are positions 3,4,5,6
type
  TInts = array of integer;
var
  i: integer;
  faces: TInts;
  vbo_point : GLuint;
begin
  if gnface < 1 then exit;
  if vao_point2d <> 0 then
     glDeleteVertexArrays(1,@vao_point2d);
  glGenVertexArrays(1, @vao_point2d);
  if (vbo_face2d <> 0) then
        glDeleteBuffers(1, @vbo_face2d);
  glGenBuffers(1, @vbo_face2d);
  vbo_point := 0;
  glGenBuffers(1, @vbo_point);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_point);
  glBufferData(GL_ARRAY_BUFFER, Length(g2Dvnc)*SizeOf(TVtxClr), @g2Dvnc[0], GL_STATIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  // Prepare vertrex array object (VAO)
  glBindVertexArray(vao_point2d);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_point);
  //Vertices
  glVertexAttribPointer(kATTRIB_VERT, 3, GL_FLOAT, GL_FALSE, sizeof(TVtxClr), PChar(0));
  glEnableVertexAttribArray(kATTRIB_VERT);
  //Color
  glVertexAttribPointer(kATTRIB_CLR, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(TVtxClr), PChar( sizeof(TPoint3f)));
  glEnableVertexAttribArray(kATTRIB_CLR);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  glDeleteBuffers(1, @vbo_point);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo_face2d);
  setlength(faces,gnface);
  for i := 0 to (gnface-1) do
      faces[i] := i;
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, gnface*sizeof(uint32), @faces[0], GL_STATIC_DRAW);
  setlength(faces, 0 );
  setlength(g2Dvnc,0);
end;

procedure nglBegin(mode: integer);
begin
     g2DNew := true;
end;

procedure nglColor4ub (r,g,b,a: byte);
begin
  g2Drgba.r := round(r );
  g2Drgba.g := round(g );
  g2Drgba.b := round(b );
  g2Drgba.a := round(a );
end;

procedure nglVertex3f(x,y,z: single);
var
  i: integer;
begin
  i := gnface; //array indexed from 0 not 1
  gnface := gnface + 1;
  if (gnface+1) > length(g2Dvnc) then
     setlength(g2Dvnc, length(g2Dvnc)+kBlockSz);
   g2Dvnc[i].vtx.X := x;
   g2Dvnc[i].vtx.Y := y;
   g2Dvnc[i].vtx.Z := z;
   g2Dvnc[i].clr := g2Drgba;
   if not g2DNew then exit;
   g2DNew := false;
   g2Dvnc[gnface] := g2Dvnc[i];
   gnface := gnface + 1;
end;

procedure nglVertex2fr(x,y: single);
begin
     nglVertex3f(round(x),round(y), -1);
end;

procedure nglEnd;
var
  i: integer;
begin
     //add tail
     if gnface < 1 then exit;
     i := gnface; //array indexed from 0 not 1
     gnface := gnface + 1;
     if gnface > length(g2Dvnc) then
        setlength(g2Dvnc, length(g2Dvnc)+kBlockSz);
     g2Dvnc[i] := g2Dvnc[i-1];
end;

procedure DrawTextCore (lScrnWid, lScrnHt: integer);
begin
  nglMatrixMode(nGL_MODELVIEW);
  nglLoadIdentity;
  nglMatrixMode (nGL_PROJECTION);
  nglLoadIdentity ();
  nglOrtho (0, lScrnWid,0, lScrnHt,-10,10);
end;
{$ELSE} //for legacy OpenGL
procedure nglColor4ub (r,g,b,a: byte);
begin
  glColor4ub (r,g,b,a);
end;

procedure nglVertex3f(x,y,z: single);
begin
     glVertex3f(x,y,z);
end;

procedure nglVertex2f(x,y: single);
begin
     glVertex2f(x,y);
end;

procedure nglBegin(mode: integer);
begin
     glBegin(mode);
end;

procedure nglVertex2fr(x,y: single);
begin
  nglVertex3f(round(x),round(y), -1);
end;

procedure nglEnd;
begin
     glEnd();
end;
{$ENDIF}

function isSame(x,y: TGLRGBQuad): boolean;
begin
     result := (x.rgbRed = y.rgbRed) and (x.rgbGreen = y.rgbGreen) and (x.rgbBlue = y.rgbBlue) and (x.rgbReserved = y.rgbReserved);
end;

procedure TGLClrbar.SetBackColor(c: TGLRGBQuad);
begin
     if not isSame(c, BackClr) then isRedraw := true;
     BackClr := c;
end;

procedure TGLClrbar.SetFontColor(c: TGLRGBQuad);
begin
     if not isSame(c, FontClr) then isRedraw := true;
     FontClr := c;
end;

procedure TGLClrbar.SetSizeFrac(f: single);
begin
     if (f <> sizeFrac) then isRedraw := true;
     sizeFrac := f;
     if sizeFrac < 0.005 then sizeFrac := 0.005;
     if sizeFrac > 0.25 then sizeFrac := 0.25;
end;

procedure TGLClrbar.SetTopOrRight(isTR: boolean);
begin
     if (isTR <> fisTopOrRight) then isRedraw := true;
     fisTopOrRight := isTR;
end;

procedure TGLClrbar.SetForcedSizeFracX(f: single);
begin
     if (f <> fForcedSizeFracX) then isRedraw := true;
     fForcedSizeFracX := f;
end;

procedure TGLClrbar.SetVertical(isV: boolean);
begin
     if (isV <> fisVertical) then isRedraw := true;
     fisVertical := isV;
end;

procedure TGLClrbar.SetLUT(index: integer; LUT: TLUT; min,max: single);
begin
     if (index > kMaxClrBar) or (index < 1) then exit;
     LUTs[index].LUT := LUT;
     LUTs[index].mn := min;
     LUTs[index].mx := max;
     isRedraw := true;
end;

procedure TGLClrbar.ScreenSize(nLUT,Width,Height: integer);
begin
     Width := Width;
     Height := Height;
     if (nLUTs = nLUT) and (Width = scrnW) and (Height = scrnH) then exit;
     scrnW := Width;
     scrnH := Height;
     nLUTs := nLUT;
     isRedraw := true;
end;

(*function setRGBA(r,g,b,a: byte): TRGBA;
begin
     result.r := r;
     result.g := g;
     result.b := b;
     result.a := a;
end;*)

{$IFDEF FPC}
constructor TGLClrbar.Create(fntname: string; Ctx: TOpenGLControl);
{$ELSE}
constructor TGLClrbar.Create(fntname: string; Ctx: TGLPanel);
{$ENDIF}
begin
     scrnH := 0;
     SizeFrac := 0.035;
     MaxTotalSizeFrac := 0.33; //do not let colorbar be > 1/3 screen size
     FontClr := RGBA(255, 255, 255, 255);
     BackClr:= RGBA(0,0,0,156);
     fisVertical := false;
     fForcedSizeFracX := 0;
     fisTopOrRight := false;
     isRedraw := true;
     //Txt := TGLText.Create('/Users/rorden/Documents/pas/OpenGLCoreTutorials/legacy/numbers.png', true, isText, Ctx);
     if (fntname = '') or (not fileexists(fntname)) then
        Txt := TGLText.Create('', isText, Ctx)
     else
         Txt := TGLText.Create(fntname, isText, Ctx);
     {$IFDEF COREGL}
     vao_point2d := 0;
     vbo_face2d := 0;
     Ctx.MakeCurrent();
     shaderProgram :=  initVertFrag(kVert2D,'', kFrag2D);
     uniform_mtx := glGetUniformLocation(shaderProgram, pAnsiChar('ModelViewProjectionMatrix'));
     glFinish;
     Ctx.ReleaseContext;
     {$ELSE}
     displayLst := 0;
     {$ENDIF}
end;

procedure TGLClrbar.CreateTicksText(mn,mx: single; BarLength, BarTop, BarThick, fntScale: single);
var
  lStep,lRange, t, lStepSize, MarkerSzX,MarkerSzY, lPosX, lPosY, StWid: single;
  lDecimals, lDesiredSteps, lPower: integer;
  isInvert: boolean;
  St: string;
begin
  if (mx = mn) or (BarThick = 0) or (BarLength = 0) then exit;
  if (mx < mn) then begin
    t := mx;
    mx := mn;
    mn := t;
  end;
  isInvert :=  (mn < 0) and (mx < 0);
  MarkerSzX := BarThick * 0.2;
  if (MarkerSzX < 1) then MarkerSzX := 1;
  if not fisVertical then begin
     MarkerSzY := MarkerSzX;
     MarkerSzX := 1;
  end else
      MarkerSzY := 1;
  //next: compute increment
  lDesiredSteps := 4;
  lRange := abs(mx - mn);
  if lRange < 0.000001 then exit;
  lStepSize := lRange / lDesiredSteps;
  lPower := 0;
  while lStepSize >= 10 do begin
  lStepSize := lStepSize/10;
        inc(lPower);
  end;
  while lStepSize < 1 do begin
       lStepSize := lStepSize * 10;
       dec(lPower);
  end;
  lStepSize := round(lStepSize) * Power(10,lPower);
  if lPower < 0 then
        lDecimals := abs(lPower)
  else
        lDecimals := 0;
  lStep := trunc((mn)  / lStepSize)*lStepSize;
  if lStep < (mn) then lStep := lStep+lStepSize;
  nglColor4ub (FontClr.rgbRed,FontClr.rgbGreen,FontClr.rgbBlue,255);//outline
  repeat
        if not fisVertical then begin
           lPosX :=   (lStep-mn)/lRange*BarLength;
           if isInvert   then
              lPosX :=   BarLength - lPosX;
           lPosX := lPosX + BarThick;
           lPosY := BarTop;
        end else begin
           lPosX := BarTop + BarThick;
           lPosY :=  (lStep-mn)/lRange*BarLength;
           if isInvert   then
              lPosY :=   BarLength - lPosY;
           lPosY := lPosY + BarThick;
        end;
        nglColor4ub (FontClr.rgbRed,FontClr.rgbGreen,FontClr.rgbBlue,255);//outline
        nglBegin(GL_TRIANGLE_STRIP);
          nglVertex2fr(lPosX-MarkerSzX,lPosY-MarkerSzY);
          nglVertex2fr(lPosX-MarkerSzX,lPosY+MarkerSzY);
          nglVertex2fr(lPosX+MarkerSzX,lPosY-MarkerSzY);
          nglVertex2fr(lPosX+MarkerSzX,lPosY+MarkerSzY);
        nglEnd;
        if fntScale > 0 then begin
           St := FloatToStrF(lStep, ffFixed,7,lDecimals);
           StWid := Txt.TextWidth(fntScale, St);
           if not fisVertical then
              Txt.TextOut(lPosX-(StWid*0.5),BarTop-(BarThick*0.82),fntScale, St)
           else
               Txt.TextOut(lPosX+(BarThick*0.82),lPosY-(StWid*0.5),fntScale,90, St)
        end;
        lStep := lStep + lStepSize;
  until lStep > (mx+(lStepSize*0.01));
end; //CreateTicksText()

procedure TGLClrbar.CreateClrbar;
var
  BGThick, BarLength,BarThick, i,b,  t,tn: integer;
  frac, pos, fntScale: single;
begin
     if nLUTs < 1 then exit; //nothing to do
     if fForcedSizeFracX > 0 then
        BarThick := round(scrnW * fForcedSizeFracX)
     else begin
        if scrnW < scrnH then
           BarThick := round(scrnW * sizeFrac)
        else
            BarThick := round(scrnH * sizeFrac);
        BGThick := round(BarThick*((nLUTs * 2)+0.5));
        if (fisVertical) and ((BGThick/scrnW) > MaxTotalSizeFrac) then begin
          BarThick := round(MaxTotalSizeFrac*(scrnW/((nLUTs * 2)+0.5)));
        end;
        if (not fisVertical) and ((BGThick/scrnH) > MaxTotalSizeFrac) then begin
          BarThick := round(MaxTotalSizeFrac*(scrnH/((nLUTs * 2)+0.5)));
        end;
     end;
     if BarThick < 1 then exit;
     if not fisVertical then
        BarLength := ScrnW - BarThick - BarThick
     else
         BarLength := ScrnH - BarThick - BarThick;
     if BarLength < 1 then exit;
     BGThick := round(BarThick*((nLUTs * 2)+0.5));
     if fisTopOrRight then begin
        if not fisVertical then
              t := scrnH-BGThick
        else
            t := scrnW - BGThick;
     end else
         t := 0;
     fntScale := 0;
     if (BarThick > 9) and (isText) then begin
        txt.ClearText;
        fntScale := (BarThick*0.7)/txt.BaseHeight;
        Txt.TextColor(FontClr.rgbRed,FontClr.rgbGreen,FontClr.rgbBlue);//black
     end;
     {$IFDEF COREGL}
     gnface := 0;
     setlength(g2Dvnc, 0);
     {$ELSE}
     if displayLst <> 0 then
        glDeleteLists(displayLst, 1);
     displayLst := glGenLists(1);
     glNewList(displayLst, GL_COMPILE);
     {$ENDIF}
     nglColor4ub (BackClr.rgbRed, BackClr.rgbGreen, BackClr.rgbBlue,BackClr.rgbReserved);
     nglBegin(GL_TRIANGLE_STRIP);
     //background
     if not fisVertical then begin
       nglVertex2fr(0,T+BGThick );
       nglVertex2fr(0,T);
       nglVertex2fr(scrnW,T+BGThick);
       nglVertex2fr(scrnW,T);
     end else begin //else vertical
         nglVertex2fr(T+BGThick,0 );
         nglVertex2fr(T,0);
         nglVertex2fr(T+BGThick,scrnH);
         nglVertex2fr(T+0, scrnH);
     end;
     nglEnd;
     frac := BarLength/255;
     for b := 1 to nLUTs do begin
         nglColor4ub (FontClr.rgbRed,FontClr.rgbGreen,FontClr.rgbBlue,255);//outline
         nglBegin(GL_TRIANGLE_STRIP);
         if not fisVertical then begin
             tn := T+BarThick*(((nLUTs - b) * 2)+1);
             nglVertex2fr(BarThick-1,tn+BarThick+1);
             nglVertex2fr(BarThick-1,tn-1);
             nglVertex2fr(BarLength+BarThick+1,tn+BarThick+1);
             nglVertex2fr(BarLength+BarThick+1,tn-1);
         end else begin
             tn := round(T+BarThick*(((b) * 2)-1.5));
             nglVertex2fr(tn+BarThick+1, BarThick-1);
             nglVertex2fr(tn-1, BarThick-1);
             nglVertex2fr(tn+BarThick+1, BarLength+BarThick+1);
             nglVertex2fr(tn-1, BarLength+BarThick+1);
         end;
         nglEnd;
         pos := BarThick;
         nglBegin(GL_TRIANGLE_STRIP);
         //MRIcroGL makes index 0 transparent
         //nglColor4ub (LUTs[b].lut[0].rgbRed, LUTs[b].lut[0].rgbGreen, LUTs[b].lut[0].rgbBlue,255);
         nglColor4ub (LUTs[b].lut[1].rgbRed, LUTs[b].lut[1].rgbGreen, LUTs[b].lut[1].rgbBlue,255);

         if not fisVertical then begin
            nglVertex2fr(pos,tn+BarThick );
            nglVertex2fr(pos,tn);
         end else begin
             nglVertex2fr(tn+BarThick,pos );
             nglVertex2fr(tn,pos);
         end;
         for i := 1 to 255 do begin
           pos := pos + frac;
           nglColor4ub (LUTs[b].lut[i].rgbRed, LUTs[b].lut[i].rgbGreen, LUTs[b].lut[i].rgbBlue,255);
           if not fisVertical then begin
              nglVertex2fr(pos,tn+BarThick);
              nglVertex2fr(pos,tn);
           end else begin
             nglVertex2fr(tn+BarThick,pos);
             nglVertex2fr(tn,pos);
           end;
         end;
         nglEnd;
         CreateTicksText(LUTs[b].mn,LUTs[b].mx, BarLength, tn, BarThick, fntScale);
     end;
     {$IFDEF COREGL}
     CreateStrips;
     {$ELSE}
     glEndList();
     {$ENDIF}
     isRedraw := false;
  end;

procedure TGLClrbar.ForceRedraw();
begin
     isRedraw := true;
end;

procedure TGLClrbar.Draw(nLUT, Width,Height, zoom,zoomOffsetX, zoomOffsetY: integer);
{$IFDEF COREGL}
var
  mvp : TnMat44;
{$ENDIF}
begin
     if nLUT < 1 then exit;
     ScreenSize(nLUT, Width,Height);
     //if zoom > 1 then
     //   glViewport(zoomOffsetX, zoomOffsetY, ScrnW, ScrnH*zoom);

     if isRedraw then
        CreateClrbar;
     {$IFDEF COREGL}
     if gnface < 1 then exit;
     glDisable(GL_CULL_FACE);
     nglMatrixMode(nGL_MODELVIEW);
     nglLoadIdentity;
     nglMatrixMode(nGL_PROJECTION);
     nglLoadIdentity();
     nglOrtho (0, Width, 0, Height, 0.1, 40);
     //glClearColor(0.3, 0.5, 0.8, 1.0); //Set blue background
     //glClear(GL_COLOR_BUFFER_BIT);
     glEnable (GL_BLEND);
     glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glDisable(GL_DEPTH_TEST);
      glUseProgram(shaderProgram);
      mvp := ngl_ModelViewProjectionMatrix;
      glUniformMatrix4fv(uniform_mtx, 1, GL_FALSE, @mvp[0,0]); // note model not MVP!
      glBindVertexArray(vao_point2d);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo_face2d);
      glDrawElements(GL_TRIANGLE_STRIP, gnface, GL_UNSIGNED_INT, nil);
      glBindVertexArray(0);
      glUseProgram(0);
     {$ELSE}
     glDisable(GL_CULL_FACE);
     glMatrixMode(GL_MODELVIEW);
     glLoadIdentity;
     glMatrixMode(GL_PROJECTION);
     glLoadIdentity();
     glOrtho (0, Width div zoom , 0, Height div zoom, 0.1, 40);
     glTranslatef(zoomOffsetX, zoomOffsetY, 0);
     glEnable (GL_BLEND);
     glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
     glDisable(GL_DEPTH_TEST);

     glCallList(displayLst);
     {$ENDIF}
     if isText then
        Txt.DrawText;
end;

{$IFDEF FPC}
procedure TGLClrbar.ChangeFontName(fntname: string; Ctx: TOpenGLControl);
{$ELSE}
procedure TGLClrbar.ChangeFontName(fntname: string; Ctx: TGLPanel);
{$ENDIF}
begin
     Txt.ChangeFontName(fntname, Ctx);
     isRedraw := true;
end;

destructor TGLClrbar.Destroy;
begin
  Txt.Free;
  //call the parent destructor:
  inherited;
end;


end.

