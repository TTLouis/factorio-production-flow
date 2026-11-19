-- Read-only exchange grouping. Never join shipments by time proximity.
local E = { SLOT = 24 }
function E.key(record, fallback)
  local a,b=record.from and record.from.id,record.to and record.to.id
  if record.exchange_id and a and b then
    a,b=tostring(a),tostring(b)
    if a>b then a,b=b,a end
    return record.exchange_id..":"..a..":"..b
  end
  return "shipment:"..tostring(record.key or record.shipment_id or fallback)
end
function E.page(groups,width,requested)
  local capacity=math.max(1,math.floor(width/E.SLOT))
  local pages=math.max(1,math.ceil(#groups/capacity))
  local page=math.max(1,math.min(requested or pages,pages))
  return page,pages,(page-1)*capacity+1,math.min(page*capacity,#groups)
end
return E
