import sys
def load(f):
    H,V,N=[],[],[]
    for ln in open(f).read().splitlines()[1:]:
        t,spr,x,y,w,h,cap=ln.split("|"); x,y,w,h=map(int,(x,y,w,h))
        if t!="sprite" or not spr.startswith("ssk-rib-d-64-"): continue
        if spr.endswith("c17") or spr.endswith("c18"): continue  # grey stubs
        r=(x,y,x+w,y+h)
        if w==32: N.append(r)
        elif w>=h: H.append(r)
        else: V.append(r)
    return H,V,N
def ov(a,b):
    w=min(a[2],b[2])-max(a[0],b[0]); h=min(a[3],b[3])-max(a[1],b[1])
    return w*h if w>1 and h>1 else 0
for f in sys.argv[1:]:
    H,V,N=load(f)
    hh=sum(ov(H[i],H[j]) for i in range(len(H)) for j in range(i+1,len(H)))
    vv=sum(ov(V[i],V[j]) for i in range(len(V)) for j in range(i+1,len(V)))
    hn=sum(ov(a,n) for a in H+V for n in N)
    print(f, "H-H %d  V-V %d  run-on-node %d px²  (pieces H%d V%d nodes%d)"%(hh,vv,hn,len(H),len(V),len(N)))
