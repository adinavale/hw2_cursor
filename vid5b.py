#!/usr/bin/python
from inspect import stack
import random

Bmap={}

class B:
    def __init__(self,name,length):
        self.name=name
        self.length=length
        self.offset=-1
        self.value=0
        self.maxval=(2**length)-1
        Bmap[name]=self
    def set(self,v):
        if v >self.maxval:
            print("Set value exceed max value",self.name)
            v=self.maxval
        self.value=v
    def get(self):
        return self.value
        

# clocking fields
Fpclk=B("Pclk",6)   # system clocks per pixel
# Memory pointers
Fbase=B("Base",32)          # base memory address for the display
Flineinc=B("Lineinc",32)    # amount to add to get to next line
Ffont=B("Font",32)          # Font table
Fcursor=B("Cursor",32)      # Cursor table location

# raster fields
Fhsize=B("Hsize",13)            # Horizontal displayed screen size in pixels
Fhsyncstart=B("Hsyncstart",13)  # Horizontal sync start in pixels
Fhsyncend=B("Hsyncend",13)      # Horizontal sync end in pixels
Fhend=B("Hend",13)              # Horizontal line end in pixels
Fvsize=B("Vsize",13)            # Vertical displayed screen size in lines
Fvsyncstart=B("Vsyncstart",13)  # Vertical sync start in lines
Fvsyncend=B("Vsyncend",13)      # Vertical sync end in lines
Fvend=B("Vend",13)              # Vertical screen end in lines
# control fields
Fenable=B("Enable",1)       # Display controller enabled
Fcurenable=B("Curenable",1) # Cursor enable
Fmode=B("Mode",2)           # Display mode (See below)
Fint=B("Int",2)             # interrupt events
Fih=B("FIH",1)              # Invert horizontal signal
Fiv=B("FIV",1)              # Invert vertical signal
Fvclk=B("Vclk",2)           # Selects the vertical clock event
Feb=B("EB",1)               # Enable Cursor Blinking
# Mode values
MD24=0      # 24 bits/pixel, RGB
MD32=1      # 32 bits/pixel, RGBA (Alpha ignored)
MD16=2      # 16 bits/pixel, 565 RGB
MDText=3    # Text mode
# Cursor fields
FcurX=B("Curx",13)          # Cursor X pixel position
FcurY=B("Cury",13)          # Cursor Y pixel position
FcurXsize=B("Cursizex",5)   # X size of the cursor (pixels)
FcurYsize=B("Cursizey",5)   # Y size of the cursor (pixels)
Fcurfg=B("Curfg",32)        # 32 bit Foreground cursor color
Fcurbg=B("Curbg",32)        # 32 bit Background cursor color
Fblink=B("Curblink",6)      # cursor blink period (Swaps FG & BG) 0=disabled
#
# Cursor format (2 bits/pixel)
#
# 00=Transparent            Screen color not modified
# 01=Invert Color           Screen color inverted
# 10=Foreground color       32 bit curfg color replaces screen color
# 11=Background color       32 bit curbg color replaces screen color
#


class REG:
    def __init__(self,regname,regaddr,fields):
        self.name=regname
        self.addr=regaddr
        self.fields=[]
        bloc=0
        fl=len(fields)
        for fw in range(len(fields)):
            fix=fl-fw-1
            f=fields[fix]
            if bloc>32:
                print("Field",f.name,"placed past bit 32")
            f.offset=bloc
            bloc+=f.length
            if bloc>32:
                print("Field",f.name,"field ends past 32 bit")
            self.fields.append(f)
#        print("Register",regname,"is",bloc,"bits")

# registers
CR=     REG("CR",0x0000,[Feb,Fvclk,Fint,Fiv,Fih,Fpclk,Fenable,Fcurenable,Fmode])
CUR0=   REG("CUR0",0x0008,[FcurX,FcurY])
CUR1=   REG("CUR1",0x0010,[Fblink,FcurXsize,FcurYsize])
CURFG=  REG("CURFG",0x0018,[Fcurfg])
CURBG=  REG("CURBG",0x0020,[Fcurbg])
H1=     REG("H1",0x0028,[Fhsize,Fhend])
H2=     REG("H2",0x0030,[Fhsyncstart,Fhsyncend])
V1=     REG("V1",0x0038,[Fvsize,Fvend])
V2=     REG("V2",0x0040,[Fvsyncstart,Fvsyncend])
BASE=   REG("BASE",0x0048,[Fbase])
LINEINC=REG("LINEINC",0x0050,[Flineinc])
FONT=   REG("FONT",0x0058,[Ffont])
CURSOR= REG("CURSOR",0x0060,[Fcursor])

regs=[CR,CUR0,CUR1,CURFG,CURBG,H1,H2,V1,V2,BASE,LINEINC,FONT,CURSOR]
regmap={}

for r in regs:
    regmap[r.name]=r

# memory model

class MEMORY:
    def __init__(self):
        self.mdata={}
    def get(self,addr):
        if not addr in self.mdata:
            return None
        return self.mdata[addr]
    def set(self,addr,data):
#        print("Setting {:x} to {:x}".format(addr,data))
        self.mdata[addr]=data
    

# working registers
wvs=[]
class WV:
    def __init__(self,v):
        global wvs
        self.this=v
        self.next=v
        self.debug=False
        wvs.append(self)
    def set(self,v):
#        if self.debug:
#            print("debug {} ({:x})".format(stack()[1].function,v))
        self.next=v
    def get(self):
        return self.this
    def inc(self,iamt=1):
        self.next=self.this+iamt
    def cycle(self):
        self.this=self.next


class WR:

    def copyreg(self):
        self.Pcnt=WV(Fpclk.value)
        self.Lcnt=WV(0)
        self.Base=WV(Fbase.value)
        self.P0ptr=WV(Fbase.value)
        self.P1ptr=WV(Fbase.value)
        self.Pptr=WV(Fbase.value)
        self.Lptr=WV(Fbase.value)
        self.Lineinc=WV(Flineinc.value)
        self.Cursor=WV(Fcursor.value)
        self.Font=WV(Ffont.value)
        self.Hsize=WV(Fhsize.value)
        self.Hsyncstart=WV(Fhsyncstart.value)
        self.Hsyncend=WV(Fhsyncend.value)
        self.Hend=WV(Fhend.value)
        self.Vsize=WV(Fvsize.value)
        self.Vsyncstart=WV(Fvsyncstart.value)
        self.Vsyncend=WV(Fvsyncend.value)
        self.Vend=WV(Fvend.value)
        self.H0cnt=WV(0)
        self.H1cnt=WV(0)
        self.Hcnt=WV(0)
        self.V0cnt=WV(0)
        self.V1cnt=WV(0)
        self.Vcnt=WV(0)
        self.Xcnt=WV(0)
        self.Ycnt=WV(0)
        self.H0blank=WV(0)
        self.H1blank=WV(0)
        self.Hblank=WV(0)
        self.H0sync=WV(0)
        self.H1sync=WV(0)
        self.Hsync=WV(0)
        self.V0sync=WV(0)
        self.V1sync=WV(0)
        self.Vsync=WV(0)
        self.V0blank=WV(0)
        self.V1blank=WV(0)
        self.Vblank=WV(0)
        self.Mode=WV(Fmode.value)
        self.W0pcnt=WV(0)
        self.W1pcnt=WV(0)
        self.Wpcnt=WV(0)
        self.R0=WV(0)
        self.R=WV(0)
        self.G0=WV(0)
        self.G=WV(0)
        self.B0=WV(0)
        self.B=WV(0)

    def DispBlank(self,bv):
        self.Hblank.set(bv)

    def DispHsync(self,sv):
        self.Hsync.set(sv)

    def DispVblank(self,bv):
        self.Vblank.set(bv)

    def DispVsync(self,sv):
        self.Vsync.set(sv)

    def StepVert(self,m):
        if self.Vcnt.get()<=self.Vsize.get():
#           print("vc",self.Vcnt.get())
           self.DispVblank(0)
           self.DispVsync(0)
           self.Vcnt.inc()
           self.Ycnt.inc()
           if self.Vcnt.get()==self.Vsize.get():
               self.DispVblank(1)
        elif self.Vcnt.get()<self.Vsyncstart.get():
#            print("VB",self.Vcnt.get(),self.Vsize.get())
            self.Lptr.set(self.Base.get())
            self.Pptr.set(self.Base.get())
            self.DispVblank(1)
            self.DispVsync(0)
            self.Vcnt.inc()
            self.Ycnt.set(0)
        elif self.Vcnt.get()<self.Vsyncend.get():
#            print("VS",self.Vcnt.get(),self.Vsize.get())
            self.Lptr.set(self.Base.get())
            self.Pptr.set(self.Base.get())
            self.DispVblank(1)
            self.DispVsync(1)
            self.Vcnt.inc()
            self.Ycnt.set(0)
        elif self.Vcnt.get()<self.Vend.get():
            self.Lptr.set(self.Base.get())
            self.Pptr.set(self.Base.get())
            self.DispVblank(1)
            self.DispVsync(0)
            self.Vcnt.inc()
            self.Ycnt.set(0)
        else:
#            print("Pptr {:x} Lptr {:x}".format(self.Pptr.get(),
#                                              self.Lptr.get()))
            self.DispVblank(0)
            self.DispVsync(0)
            self.Vcnt.set(0)
            self.Ycnt.set(0)
#            self.GetPixelData(m)

    def GetPixelDatax(self,m):
        waddr=self.Pptr.get()
        if self.Mode.get()==MD32:  # supported mode now
            pd=m.get(waddr)
            if pd==None:
                print("Pd none @ {:x}".format(waddr))
                return
            self.B.set(pd&0xff)
            self.G.set((pd>>8)&0xff)
            self.R.set((pd>>16)&0xff)
        else:               # unsupported mode
            self.B.set(-1)
            self.R.set(-1)
            self.G.set(-1)

    def ProcCur(self,m):
        if Fcurenable.get()!=1 or Fenable.get()!=1:
            return
        if self.Vcnt.get()>=FcurY.get() and (FcurY.get()+FcurYsize.get())>=self.Vcnt.get():
            if self.Hcnt.get()>=FcurX.get() and (FcurX.get()+FcurXsize.get())>=self.Hcnt.get():
                curline=self.Vcnt.get()-FcurY.get()
                pd0=m.get(self.Cursor.get()+curline*8)
                pd1=m.get(self.Cursor.get()+curline*8+4)
                pd=(pd1<<32)+pd0
                curpix=self.Hcnt.get()-FcurX.get()
                cpix=(pd>>(curpix*2))&0x3
#                print("pptr {:x} v {} h {} pd {:08x} curpix {} cpix {} R {:02x} G {:02x}".format(self.Pptr.get(),
#                        self.Vcnt.get(),
#                        self.Hcnt.get(),pd,curpix,cpix,self.R.next,self.G.next))
                if cpix==1:
                    self.R.set(0xff^self.R.next)
                    self.G.set(0xff^self.G.next)
                    self.B.set(0xff^self.B.next)
                elif cpix==2:
                    self.R.set((Fcurfg.get()>>16)&0xff)
                    self.G.set((Fcurfg.get()>> 8)&0xff)
                    self.B.set((Fcurfg.get()    )&0xff)
                elif cpix==3:
                    self.R.set((Fcurbg.get()>>16)&0xff)
                    self.G.set((Fcurbg.get()>> 8)&0xff)
                    self.B.set((Fcurbg.get()    )&0xff)
        
    def DispPixel(self,m):
        if self.Hblank.get()==0 and self.Vblank.get()==0:
            self.GetPixelDatax(m)
            self.ProcCur(m)
        else:
            self.R.set(0)
            self.G.set(0)
            self.B.set(0)
        
    def step_pixel(self,m):
        if self.Hcnt.get()<self.Hsize.get():
#            self.DispPixel(m)
            self.Hcnt.inc()
            self.Xcnt.inc()
        elif self.Hcnt.get()==self.Hsize.get():
            if self.Vblank.get()==0:
                self.Lptr.inc(self.Lineinc.get())
                self.Pptr.set(self.Lptr.get()+self.Lineinc.get())
            self.Xcnt.set(0)
            self.DispBlank(1)
            self.Hcnt.inc()
        elif self.Hcnt.get()<self.Hsyncstart.get():
            self.DispBlank(1)
            self.Hcnt.inc()
            self.Xcnt.set(0)
        elif self.Hcnt.get()<self.Hsyncend.get():
            self.DispHsync(1)
            self.DispBlank(1)
            self.Hcnt.inc()
            if self.Hcnt.get()==self.Hsyncstart.get():
                self.StepVert(m)
            self.Xcnt.set(0)
        elif self.Hcnt.get()<self.Hend.get():
            self.DispHsync(0)
            self.DispBlank(1)
            self.Hcnt.inc()
            self.Xcnt.set(0)
        else:
#            self.DispPixel(m)
            self.DispBlank(0)
#            if self.Vcnt.get()<=self.Vsize.get():
#                self.DispPixel(m)
            self.Hcnt.set(0)
            self.Xcnt.set(0)

    def step_pipe(self):
        self.H0sync.set(self.Hsync.get())
        self.H0blank.set(self.Hblank.get())
        self.V0sync.set(self.Vsync.get())
        self.V0blank.set(self.Vblank.get())
        self.H1sync.set(self.H0sync.get())
        self.H1blank.set(self.H0blank.get())
        self.V1sync.set(self.V0sync.get())
        self.V1blank.set(self.V0blank.get())
        self.R0.set(self.R.get())
        self.G0.set(self.G.get())
        self.B0.set(self.B.get())
        self.P0ptr.set(self.Pptr.get())
        self.P1ptr.set(self.P0ptr.get())
        self.V0cnt.set(self.Vcnt.get())
        self.V1cnt.set(self.V0cnt.get())
        self.H0cnt.set(self.Hcnt.get())
        self.H1cnt.set(self.H0cnt.get())
        self.W0pcnt.set(self.Wpcnt.get())
        self.W1pcnt.set(self.W0pcnt.get())
    
    def step(self,m):
#        if self.Wpcnt.get()==0:
#            if self.Hblank.get()==0 and self.Vblank.get()==0:
#                self.Pptr.inc(4)
        if self.Wpcnt.get()>=self.Pcnt.get():
            self.Wpcnt.set(0)
            if self.Hblank.get()==0 and self.Vblank.get()==0:
                self.Pptr.inc(4)
            self.step_pixel(m)
        else:
#            self.DispPixel(m)
            self.Wpcnt.inc()
        self.DispPixel(m)
        self.step_pipe()
        return

def RGB(r,g,b):
    rv=(b&0xff)|((g&0xff)<<8)|((r&0xff)<<16)
    return rv
    

def setrgb1(m,adr,lskip,hs,vs):
    for y in range(vs+2):
        for x in range(hs+2):
            m.set(adr+(y*lskip)+x*4,RGB(x+128,x+y,y+64))

def setrcursor(m,adr):
    for x in range(2*32):
        m.set(adr+x*4,random.randint(0,0xffff_ffff))


def setupcase1():
    m=MEMORY()
    Fpclk.set(2)
    Fvclk.set(1)
    Fenable.set(1)
    Fbase.set(0x4000)
    Flineinc.set(0x1000)
    Ffont.set(0x20000)
    Fcursor.set(0x40000)
    Fhsize.set(57)
    Fhsyncstart.set(63)
    Fhsyncend.set(65)
    Fhend.set(77)
    Fvsize.set(23)
    Fvsyncstart.set(25)
    Fvsyncend.set(27)
    Fvend.set(32)
    Fmode.set(MD32)
    Fenable.set(1)
    Fcurenable.set(0)
    FcurX.set(5)
    FcurY.set(5)
    FcurXsize.set(9)
    FcurYsize.set(9)
    Fcurfg.set(RGB(10,20,250))
    Fcurbg.set(RGB(11,11,0))
    Fblink.set(0)
    Fcurenable.set(1)
    setrgb1(m,Fbase.get(),Flineinc.get(),Fhsize.get()+1,Fvsize.get()+1)
    setrcursor(m,Fcursor.get())
    
    w=WR()
    w.copyreg()
    w.Pptr.set(Fbase.value)
    return(w,m)

def BB(w1,clr):
#    if w1.Hblank.get()==1 or w1.Vblank.get()==1:
#        return 0
    return clr.get()

def barf(fw,cc,w1):
    fw.write("clk {:4d} Pptr {:08x} PC {:2d} HC {:2d} HS {} HB {} VS {} VB {} Vcnt {:4d} RGB {:02x} {:02x} {:02x}\n".format(cc,
            w1.P1ptr.get(),                                                                                                                        
            w1.W1pcnt.get(),
            w1.H1cnt.get(),w1.H1sync.get(),
            w1.H1blank.get(),
            w1.V1sync.get(),
            w1.V1blank.get(),w1.V1cnt.get(),BB(w1,w1.R0),
            BB(w1,w1.G0),BB(w1,w1.B0) ))

def rbits(flds):
    last=len(flds)-1
    rv=0
    sl=0
    for iu in range(len(flds)):
        ix=iu
        f=flds[ix]
        print(ix,f.name,sl,"Value","{:x}".format(f.get()))
        rv |= f.value << sl
        sl+= f.length
    return rv
        

def dumpregs(fo,regs):
    for r in regs:
        fo.write("# {} at offset {:04x}\n".format(r.name,r.addr))
        fo.write("R {:04x} {:08x}\n".format(r.addr,rbits(r.fields)))

def dumpmem(fo,mem):
    for m in mem.mdata:
        d=mem.mdata[m]
        fo.write("m {:08x} {:08x}\n".format(m,d))

def dumpixel(fo,w):
    r=w.R0.get()
    g=w.G0.get()
    b=w.B0.get()
#    if w.Vblank.get()==1:
#        r=0
#        g=0
#        b=0
    fo.write("p {:x} {:x} {:x} {:x} {:02x} {:02x} {:02x}\n".format(w.H1sync.get(),
        w.H1blank.get(),
        w.V1sync.get(),w.V1blank.get(),r,g,b))
    
(w1,m1)=setupcase1()

w1.GetPixelDatax(m1)
ft=open("t2.trace","w")

def cycleit():
    global wvs
    for w in wvs:
        w.cycle()

with open("t2.test","w") as ftst:
    dumpregs(ftst,regs)
    dumpmem(ftst,m1)
    w1.GetPixelDatax(m1)
#    w1.step(m1)
    for w in wvs:
        w.cycle()
#    barf(ft,0,w1)
#    dumpixel(ftst,w1)
    print("Fhend",Fhend.value,"Fvend",Fvend.value,"fpclk",Fpclk.value)
    w1.step(m1) # allow pipe to reach outputs
    cycleit()
#    w1.step(m1)
    
    for cc in range(1,2*(Fhend.value+1)*(Fvend.value+1)*(Fpclk.value+1)):
        w1.step(m1)
        cycleit()
        barf(ft,cc,w1)
        dumpixel(ftst,w1)


ft.close()
    
