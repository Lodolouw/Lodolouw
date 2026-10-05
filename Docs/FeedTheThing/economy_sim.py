"""Economy simulation for Feed the Thing in the Basement.

A greedy, always-active bot plays for HOURS and we print when it reaches each
milestone (median of 20 runs). Change the numbers at the top, rerun, compare.
    python3 economy_sim.py
Real players are slower; read the times as "the fastest a keen player gets there".
"""
import random, sys, statistics
# name, seed cost, regrow s, toss coins, shop chance, creature, cps, grow s
CROPS = [
 ("Tomato",     10,       15, 3,    1.00, "Blorp",    1,    120),
 ("Chili",      50,       20, 8,    1.00, "Sizzle",   3,    180),
 ("Eyeberry",   750,      45, 30,   0.80, "Peeper",   10,   600),
 ("Glowshroom", 7500,     75, 100,  0.60, "Glumcap",  30,   900),
 ("Pumpkin",    100000,   100,400,  0.40, "Gourdo",   100,  1800),
 ("MoonMelon",  1000000,  180,2000, 0.20, "Moonmoth", 500,  7200),
]
MISH = ("Mishmash", 175, 2700)
MAXPLOTS = 10
PLOT_COST = {5:150, 6:1000, 7:5000, 8:25000, 9:150000, 10:750000}
YARD_COST = {9:2000, 10:8000, 11:30000, 12:100000, 13:300000, 14:1000000, 15:3000000, 16:10000000}
SIZE_XP = [0, 100, 3000, 50000, 800000]
SIZE_COIN = [1, 1.25, 1.5, 2, 3]
SIZE_HATCH = [0.25, 0.3, 0.35, 0.45, 0.6]
HOURS = 8
TOSS_EVERY = 2.5
AVG_TOSS_MULT = 2.5  # cravings x3 and combo, averaged over all tosses
MUT_EV = 1.12
SELL_SECONDS = 30
ACTIVE = 0.8   # fraction of food actually tossed promptly (player AFK sometimes)

def run(seed, verbose=False):
    rnd = random.Random(seed)
    st = dict(coins=0.0, xp=0, size=0)
    plants = [[0,0,2],[0,0,1]]
    plots = 4; basket=[0]*6; belly=[]; yard=[]; yard_cap=8; stock=[0]*6
    M = {}; log=[]
    def ms(k,t):
        if k not in M: M[k]=t
    def cps_of(c):
        p=min(1,c[3]/c[2]); return c[1]*c[4]*(c[5]+(1-c[5])*p)
    t=0; nexttoss=5
    while t <= HOURS*3600:
        if t%300==0:
            for i,c in enumerate(CROPS):
                stock[i] = 99 if c[4]>=1 else (rnd.randint(1,3 if i<4 else 1) if rnd.random()<c[4] else 0)
            if t%3600==0 and t>0: stock[5]=max(stock[5],1)
        for p in plants:
            if p[2]<3:
                p[1]+=1
                if p[1]>=CROPS[p[0]][2]: p[1]=0; p[2]+=1
        if t%5==0:
            for p in plants: basket[p[0]]+=p[2]; p[2]=0
        if t>=nexttoss and rnd.random()<ACTIVE:
            have=[i for i in range(6) if basket[i]>0]
            if have:
                f=max(have)
                basket[f]-=1
                base=CROPS[f][3]
                st['coins']+=base*AVG_TOSS_MULT*SIZE_COIN[st['size']]
                st['xp']+=base
                while st['size']<4 and st['xp']>=SIZE_XP[st['size']+1]:
                    st['size']+=1; ms("size%d"%(st['size']+1),t)
                belly.append(f)
                if len(belly)>=(3 if st['size']==0 else 5):
                    cnt={}
                    for x in belly: cnt[x]=cnt.get(x,0)+1
                    if len(cnt)>=5: name,cps,grow=MISH
                    else:
                        b=max(cnt.items(),key=lambda kv:(kv[1],kv[0]))[0]
                        name,cps,grow=CROPS[b][5],CROPS[b][6],CROPS[b][7]
                    ms("hatch:"+name,t)
                    new=[name,cps,grow,0,MUT_EV,SIZE_HATCH[st['size']]]
                    if len(yard)<yard_cap: yard.append(new)
                    else:
                        w=min(yard,key=lambda c:c[1])
                        if cps>w[1]: st['coins']+=w[1]*w[4]*SELL_SECONDS; yard.remove(w); yard.append(new)
                        else: st['coins']+=cps*MUT_EV*SELL_SECONDS
                    belly.clear(); nexttoss=t+4
                else: nexttoss=t+TOSS_EVERY
        for c in yard:
            c[3]+=1; st['coins']+=cps_of(c)
        if t%5==0:
            changed=True
            while changed:
                changed=False
                worst=min(plants,key=lambda p:p[0])
                for i in range(5,-1,-1):
                    if stock[i]>0 and st['coins']>=CROPS[i][1]:
                        if len(plants)<plots:
                            st['coins']-=CROPS[i][1]; stock[i]-=1; plants.append([i,0,0]); ms("seed:"+CROPS[i][0],t); changed=True; break
                        elif worst[0]<i:
                            # replace the weakest plant (its seed price comes back in full)
                            st['coins']+=CROPS[worst[0]][1]-CROPS[i][1]; stock[i]-=1; worst[0]=i; worst[1]=0; worst[2]=0; ms("seed:"+CROPS[i][0],t); changed=True; break
                if changed: continue
                if plots<MAXPLOTS and st['coins']>=PLOT_COST[plots+1]:
                    st['coins']-=PLOT_COST[plots+1]; plots+=1; ms("plot%d"%plots,t); changed=True; continue
                if len(yard)>=yard_cap and yard_cap<16 and st['coins']>=YARD_COST[yard_cap+1]:
                    st['coins']-=YARD_COST[yard_cap+1]; yard_cap+=1; ms("yard%d"%yard_cap,t); changed=True
        if t%600==0:
            log.append((t//60,int(st['coins']),round(sum(cps_of(c) for c in yard),1),st['size']+1,plots,yard_cap))
        t+=1
    return M,log

seeds=range(1,21)
runs=[run(s) for s in seeds]
keys=["hatch:Blorp","seed:Chili","size2","hatch:Sizzle","seed:Eyeberry","hatch:Peeper","size3","seed:Glowshroom","hatch:Glumcap","seed:Pumpkin","hatch:Gourdo","size4","hatch:Mishmash","seed:MoonMelon","hatch:Moonmoth","size5","plot10","yard16"]
for k in keys:
    v=[r[0].get(k) for r in runs]; got=[x for x in v if x is not None]
    if got: print(f"{k:18s} median {statistics.median(got)/60:6.1f} min  range {min(got)/60:5.1f}-{max(got)/60:5.1f}  ({len(got)}/{len(v)})")
    else: print(f"{k:18s} never")
print()
print('run 1, every 10 min: (minute, coins, coins/s, thing size, plots, yard)')
for row in runs[0][1]: print(row)
