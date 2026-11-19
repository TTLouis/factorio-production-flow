local E=require("scripts.transfer_exchanges")
local a,b,c={id=1},{id=2},{id=3}
local item=function(n,q) return {{name="iron-plate",count=n,quality=q or "normal"}} end
local rows={
 {key="up",exchange_id=1,from=a,to=b,direction="exports",tick=10,sent=item(20)},
 {key="down",exchange_id=1,from=b,to=a,direction="imports",tick=11,arrival_tick=20,received=item(30)},
 {key="return",exchange_id=2,from=a,to=b,direction="exports",tick=30,sent=item(7)},
 {key="other-surface",exchange_id=1,from=a,to=c,direction="exports",tick=15,sent=item(3)},
 {key="legacy-one",from=a,to=b,direction="exports",tick=40,sent=item(2)},
 {key="legacy-two",from=a,to=b,direction="exports",tick=40,sent=item(4)},
 {key="empty",exchange_id=3,from=a,to=b,direction="imports",tick=45,arrival_tick=50,received={}},
 {key="unknown",from=b,to=a,direction="imports",tick=55,sent=item(100)},
 {key="rare",exchange_id=4,from=a,to=b,direction="exports",tick=60,sent=item(9,"rare")}}
local result=E.build(rows,0,100,"iron-plate")
assert(#result==7,"Visits, distinct endpoint pairs, legacy shipments, empty cargo or unknown observations conflated")
local first=result[1]
assert(first.sent==20 and first.received==30 and first.first_tick==10 and first.last_tick==20,
 "Both sides of a real exchange must share a position without netting quantities")
assert(first.records.up and first.records.down)
local unknown
for _,r in ipairs(result) do if r.records.unknown then unknown=r end end
assert(unknown and unknown.unknown and not unknown.received_known and unknown.received==0,"Dispatch became a receipt")
assert(unknown.inbound_dispatch==100 and unknown.inbound_dispatch_known and not unknown.unmeasured,
  "A witnessed inbound manifest must be a separate quantity from measured receipts")
assert(#E.build(rows,0,100,"iron-plate","rare")==2,"Quality scope merged known zero with unknown")
assert(#E.build(rows,21,39,"iron-plate")==1,"Window retained an exchange with no matching cargo")
local saved=prototypes
prototypes={item={["iron-plate"]={stack_size=100},armor={stack_size=1}}}
local rocket={key="rocket",direction="imports",method="rocket",from=a,to=b,tick=20,
  sent={{name="iron-plate",count=100},{name="iron-plate",count=1,quality="rare"},{name="armor",count=5}},
  cargo_loss=.2,pad_miss=.25}
local estimated=E.build({rocket},0,100)[1]
assert(estimated.estimated_dispatch==106 and estimated.inbound_estimate==94 and not estimated.received_known)
local filtered=E.build({rocket},0,100,"iron-plate","rare")[1]
assert(filtered.inbound_estimate==1 and filtered.estimated_dispatch==1,"Singleton and quality scope changed")
rocket.status="padless"
assert(E.build({rocket},0,100,"iron-plate","normal")[1].inbound_estimate==80.5,"Padless landing did not refine the estimate")
rocket.received=item(89)
rocket.arrival_tick=30
local measured=E.build({rocket},0,100,"iron-plate")[1]
assert(measured.first_tick==30 and measured.received==89 and not measured.inbound_estimate_known)
prototypes=saved
-- SE landings known not to be whole receipts draw no quantity, never a full dispatch.
local spill={key="spill",direction="imports",method="cannon",from=a,to=b,tick=70,status="spilled",landed_tick=190,sent=item(100)}
local spilled=E.build({spill},0,100,"iron-plate")[1]
assert(spilled.unmeasured and spilled.unknown and not spilled.inbound_dispatch_known,"Spilled shot drawn as a full delivery")
spill.status,spill.landed_tick="in-flight",nil
assert(E.build({spill},0,100,"iron-plate")[1].inbound_dispatch==100,"In-flight shot lost its dispatch")
local offpad={key="offpad",direction="imports",method="rocket",from=a,to=b,tick=70,status="padless",sent=item(100)}
assert(E.build({offpad},0,100,"iron-plate")[1].unmeasured,"Off-pad landing without an estimate drawn as dispatch")
offpad.method="cargo-pod";offpad.status=nil;offpad.landed_tick=80
assert(E.build({offpad},0,100,"iron-plate")[1].inbound_dispatch==100,"Space Age dispatch changed by SE outcomes")
local groups={};for i=1,1000 do groups[i]={key=tostring(i)} end
local page,pages,start,finish=E.page(groups,240)
assert(E.SLOT==24 and page==100 and pages==100 and start==991 and finish==1000,"Compact layout silently dropped history")
page,pages,start,finish=E.page(groups,240,1)
assert(page==1 and start==1 and finish==10,"Explicit history page did not remain selected")
print("TRANSFER EXCHANGES PASS: mixed visits, real identities, legacy separation, empty/unknown cargo, quality/window scope and compact pagination")
