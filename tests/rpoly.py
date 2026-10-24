import sys, re
from PIL import Image, ImageDraw, ImageFont
def render(txt, dst, W, H, ox):
    img=Image.new("RGBA",(W,H),(0,0,0,255))
    def px(x,y): return ((x-ox)*32, y*32)
    for ln in open(txt+".poly").read().splitlines():
        k,c,data=ln.split("|"); r,g,b,a=map(float,c.split(","))
        # premultiplied -> straight
        col=(int(min(255,r/a*255)) if a else 0,int(min(255,g/a*255)) if a else 0,int(min(255,b/a*255)) if a else 0,int(a*255))
        layer=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
        if k=="R":
            x0,y0,x1,y1=map(float,data.split(",")); d.rectangle((*px(x0,y0),*px(x1,y1)),fill=col)
        else:
            pts=[px(*map(float,p.split(","))) for p in data.split(";")]
            for i in range(len(pts)-2):
                a,b,c=pts[i:i+3]
                # GPU triangle strips discard degenerate connector triangles.
                if abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])) > 1e-6:
                    d.polygon([a,b,c],fill=col)
        img.alpha_composite(layer)
    # overlay GUI labels/buttons from the txt
    d=ImageDraw.Draw(img)
    font=ImageFont.load_default(size=17)
    colors=[list(map(float, row.split(','))) for row in open(txt + ".palette")]
    for ln in open(txt).read().splitlines()[1:]:
        t,spr,x,y,w,h,cap=ln.split("|"); x,y,w,h=map(int,(x,y,w,h))
        if t=="sprite-button": d.rectangle((x,y,x+w,y+h),outline=(200,200,200))
        elif t=="sprite" and re.match(r"ssk-rib-d-64-c\d+",spr):
            color=colors[int(spr[-2:])-1]
            layer=Image.new("RGBA",(max(1,w),max(1,h)),tuple(map(int,color[:3]))+(int(color[3]*255),))
            img.alpha_composite(layer,(x,y))
        elif t=="label":
            layer=Image.new("RGBA",(max(1,w),max(1,h)))
            ImageDraw.Draw(layer).text((0,0),re.sub(r"\[/?color[^\]]*\]","",cap),fill=(230,230,230),font=font)
            img.alpha_composite(layer,(x,y))
    img.convert("RGB").save(dst)
render(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]))
