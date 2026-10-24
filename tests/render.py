import sys, re
from PIL import Image, ImageDraw, ImageFont
FNT=ImageFont.load_default(size=17); FNT2=ImageFont.load_default(size=20)
atlas = Image.open("graphics/ribbons.png"); elb = Image.open("graphics/elbows.png"); atlas_t = None
cols=[(0xE6,0x19,0x4B),(0x3C,0xB4,0x4B),(0xFF,0xE1,0x19),(0x4F,0x7B,0xFF),(0xF5,0x82,0x31),(0xB1,0x5C,0xE0),(0x46,0xF0,0xF0),(0xF0,0x32,0xE6),(0xBC,0xF6,0x0C),(0xFA,0xBE,0xBE),(0x1F,0xB5,0xA8),(0xE6,0xBE,0xFF),(0xC0,0x80,0x40),(0xFF,0xFA,0xC8),(0xAA,0xFF,0xC3),(0xFF,0xD8,0xB1),(0xA0,0xA0,0xA0),(0x80,0x80,0x80)]
ALPHA={17:0.6,18:0.16}
import os
# Match actual GUI visibility by default; optional debug names are not game UI.
SKIPNAME=os.getenv("SKIPNAME", "1")=="1"
def render(src, dst):
    palette_colors, palette_alphas = cols, ALPHA
    if os.path.exists(src + ".palette"):
        rows = [list(map(float, row.split(','))) for row in open(src + ".palette")]
        palette_colors = [tuple(map(int, row[:3])) for row in rows]
        palette_alphas = {i + 1: row[3] for i, row in enumerate(rows)}
    lines=open(src).read().splitlines()
    _,W,H,VH=lines[0].split()
    img=Image.new("RGBA",(int(W),int(H)),(64,64,64,255)); d=ImageDraw.Draw(img)
    for ln in lines[1:]:
        t,spr,x,y,w,h,cap=ln.split("|"); x,y,w,h=map(int,(x,y,w,h))
        if t=="sprite" and spr.startswith("ssk-bg") or t=="sprite" and spr.startswith("ssk-line"):
            c=int(spr[-2:]); al=26 if "bg" in spr else 90
            ov=Image.new("RGBA",(max(1,w),max(1,h)),palette_colors[c-1]+(al,)); img.alpha_composite(ov,(x,y)); continue
        if t=="sprite" and spr.startswith("ssk-elb-"):
            m=re.match(r"ssk-elb-(\w\w)-(\d+)-c(\d+)",spr); ci=["bl","tr","tl","br"].index(m[1]); k=int(m[2]); c=int(m[3])
            idx=ci*32+k-1; cx=(idx%16)*128; cy=(idx//16)*128
            cell=elb.crop((cx,cy,cx+128,cy+128)).resize((max(1,w),max(1,h)),Image.BILINEAR)
            a=cell.split()[3].point(lambda v,c=c:int(v*palette_alphas.get(c,0.86)))
            layer=Image.new("RGBA",cell.size,palette_colors[c-1]+(0,)); layer.putalpha(a); img.alpha_composite(layer,(x,y)); continue
        if t=="sprite" and spr=="ssk-node-hit": continue
        if t=="sprite":
            m=re.match(r"ssk-rib(t?)-(d|u)-(\d+)-c(\d+)",spr); tall=m[1]=="t"; di=0 if m[2]=="d" else 1; k=int(m[3]); c=int(m[4])
            if tall:
                idx=di*50+k-1; cx=(idx%32)*128; cy=(idx//32)*1024; cell=atlas_t.crop((cx,cy,cx+128,cy+1024))
            else:
                idx=di*64+k-1; cx=(idx%10)*384; cy=(idx//10)*256; cell=atlas.crop((cx,cy,cx+384,cy+256))
            cell=cell.resize((max(1,w),max(1,h)),Image.BILINEAR)
            a=cell.split()[3].point(lambda v,c=c:int(v*palette_alphas.get(c,0.86)))
            layer=Image.new("RGBA",cell.size,palette_colors[c-1]+(0,)); layer.putalpha(a)
            img.alpha_composite(layer,(x,y))
        elif t=="sprite-button":
            d.rectangle((x,y,x+w,y+h),fill=(150,150,150),outline=(30,30,30))
            if spr and not SKIPNAME:
                nm=(cap or spr.split("/",1)[-1]).replace("-"," ")
                bb=d.textbbox((0,0),nm,font=FNT2); tw=bb[2]-bb[0]
                d.rectangle((x+w+4,y-20,x+w+8+tw,y+2),fill=(30,30,30,200))
                d.text((x+w+6,y-20),nm,fill=(255,255,255),font=FNT2)
        elif t=="label":
            cap=re.sub(r"\[/?color[^\]]*\]","",cap)
            # Match the GUI's fixed-size, single-line label box.
            text_layer=Image.new("RGBA",(max(1,w),max(1,h)))
            ImageDraw.Draw(text_layer).text((0,0),cap,fill=(230,230,230),font=FNT)
            img.alpha_composite(text_layer,(x,y))
    img.convert("RGB").save(dst)
for n in sys.argv[2:]: render(f"{sys.argv[1]}/{n}.txt", f"{sys.argv[1]}/{n}.png")
