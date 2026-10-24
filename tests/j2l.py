import json,sys
def lua(v):
    if isinstance(v,dict): return "{"+",".join("[%s]=%s"%(json.dumps(k),lua(x)) for k,x in v.items())+"}"
    if isinstance(v,list): return "{"+",".join(lua(x) for x in v)+"}"
    if isinstance(v,bool): return "true" if v else "false"
    if v is None: return "nil"
    if isinstance(v,str): return json.dumps(v)
    return repr(v)
d=json.load(open(sys.argv[1])); s=sys.argv[2]
r=d['replay_surfaces'][s]
open(sys.argv[3],'w').write("return "+lua(r))
