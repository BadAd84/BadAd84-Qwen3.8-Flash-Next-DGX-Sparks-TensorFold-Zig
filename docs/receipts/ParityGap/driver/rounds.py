import re, glob, os, statistics
DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) tok/wall ([\d.]+) tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
def cell(root, arm, c, kind):
    tot={'t':0,'r':0,'d':0,'a':0,'w':0.0,'agg':[]}
    for line in open(os.path.join(root, arm, f"c{c}", "run1", "dec.log"), errors="replace"):
        m=DEC.match(line)
        if not m or m[2]!=kind: continue
        tot['t']+=int(m[8]); tot['r']+=int(m[9]); tot['d']+=int(m[10]); tot['a']+=int(m[11])
        tot['w']+=int(m[8])/float(m[7]); tot['agg'].append(float(m[6]))
    if not tot['r']: return None
    return {'agg': statistics.median(tot['agg']), 'tokr': tot['t']/tot['r'], 'ms': 1000*tot['w']/tot['r'],
            'acc': tot['a']/tot['d'] if tot['d'] else None}
root="work/ParityGap/ev"
print("level kind | P agg  D agg  ratio | P tok/r D tok/r | P ms/r D ms/r | ms ratio")
for c in (1,2,4,6,8):
    for kind in ("prose","code"):
        P=cell(root,"P",c,kind); D=cell(root,"D",c,kind)
        if not P or not D: continue
        print(f"{c} {kind:5s} | {P['agg']:6.1f} {D['agg']:6.1f} {D['agg']/P['agg']:.3f} | {P['tokr']:.2f} {D['tokr']:.2f} | {P['ms']:5.1f} {D['ms']:5.1f} | {D['ms']/P['ms']:.3f}")
