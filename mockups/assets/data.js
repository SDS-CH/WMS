/* ============================================================
   WMS MOCKUPS — MOCK DATASET
   One coherent, cross-referenced dataset. The same IDs appear
   across sections: an LPN received in Goods Reception shows up
   as a Putaway task, then as Stock-on-Hand, then gets Picked.
   This is what makes the click-through feel like one system.
   ============================================================ */
const DB = {
  clients: [
    // allowBackorder: outbound remainder policy. false = short-close (ship what's there, cancel the rest);
    // true = back-order (the unshipped remainder stays open and re-enters allocation when stock arrives).
    { id: 'C-ACME', name: 'ACME Foods Ltd', legal: 'ACME Foods Limited',
      contact: 'Marie Dubois', email: 'ops@acmefoods.example', phone: '+41 22 555 0101',
      country: 'Switzerland', status: 'active', sites: ['S-LYON','S-PARIS'], allowBackorder: false },
    { id: 'C-GLBX', name: 'Globex Pharma', legal: 'Globex Pharmaceuticals SA',
      contact: 'Nicolas Masserey', email: 'logistics@globex.example', phone: '+41 21 555 0199',
      country: 'Switzerland', status: 'active', sites: ['S-LYON'], allowBackorder: true },
  ],

  // ---- Suppliers (GLOBAL master — the source of inbound goods; referenced by an ASN header) ----
  suppliers: [
    { id:'SUP-100', name:'Mediterranea Foods SpA', contact:'Giulia Romano', email:'export@mediterranea.example', phone:'+39 02 555 0140', country:'Italy',       status:'active' },
    { id:'SUP-200', name:'Globex Pharma Mfg',      contact:'Dr. Anaya Rao',  email:'supply@globex-mfg.example', phone:'+41 61 555 0170', country:'Switzerland', status:'active' },
  ],
  // ---- Carriers (GLOBAL master — who physically moves the goods out; referenced on dispatch / delivery note) ----
  carriers: [
    { id:'CAR-EFR', name:'EuroFreight SA',     scac:'EFRS', mode:'Road',          contact:'Dispatch desk', phone:'+33 4 555 0188', status:'active' },
    { id:'CAR-CCX', name:'ColdChain Express',  scac:'CCXP', mode:'Road · 2–8 °C', contact:'Cold ops',      phone:'+33 4 555 0190', status:'active' },
  ],
  // ---- Consignees / ship-to (CLIENT-scoped — the client's delivery points / end customers) ----
  // KEY 3PL distinction: an outbound order ships to one of its client's CONSIGNEES, not to the client itself.
  // The client owns the stock; the consignee is where it is delivered.
  consignees: [
    { id:'CNE-AC01', client:'C-ACME', name:'Carrefour Part-Dieu', address:'17 Rue du Docteur Bouchut', city:'Lyon',     country:'France', contact:'Receiving dock',    phone:'+33 4 555 0201', status:'active' },
    { id:'CNE-AC02', client:'C-ACME', name:'Auchan Grand Sud',    address:'2 Av. de l’Europe',          city:'Toulouse', country:'France', contact:'Goods-in',          phone:'+33 5 555 0202', status:'active' },
    { id:'CNE-GX01', client:'C-GLBX', name:'CHU Lyon — Pharmacie',address:'103 Gde Rue de la Croix-Rousse', city:'Lyon', country:'France', contact:'Hospital pharmacy', phone:'+33 4 555 0210', status:'active' },
  ],

  // `levels` = the per-site addressing path (human-readable code only).
  // `areas`  = managed logical areas for SLOTTING + SEGREGATION, decoupled from the path.
  //            Each storage location is assigned to one area code. An area carries its own
  //            category affinity and (optional) owningClient. Renaming/restructuring `levels`
  //            never affects areas.
  sites: [
    { id: 'S-LYON',  name: 'Luanda',     city:'Luanda', country:'Angola', type:'Distribution Centre', status:'active',
      levels:['Floor','Zone','Aisle','Rack','Bin'],
      areas:[
        { code:'A', name:'Area A — Ambient',    preferredCategories:['CAT-FB'],     preferredSubCategories:['SUB-OIL','SUB-DRY'], owningClient:'' },
        { code:'B', name:'Area B — Cold chain', preferredCategories:['CAT-PHARMA'], preferredSubCategories:['SUB-VAX'],           owningClient:'C-GLBX' },
      ] },
    { id: 'S-PARIS', name: 'Soyo',       city:'Soyo',  country:'Angola', type:'Cross-dock Hub',       status:'active',
      levels:['Zone','Aisle'],
      areas:[
        { code:'C', name:'Area C — Cross-dock', preferredCategories:[], preferredSubCategories:[], owningClient:'' },
      ] },
  ],
  // Structure applied to a brand-new site; the user can edit it afterwards on the Site screen.
  defaultLocationLevels: ['Zone','Aisle','Rack','Bin'],

  // Cross-client product taxonomy (two levels: category -> sub-categories). Global, like UoM.
  categories: [
    { id:'CAT-FB',     name:'Food & Beverage', subs:[
      { id:'SUB-OIL', name:'Oils & Condiments' },
      { id:'SUB-DRY', name:'Dry Goods' },
      { id:'SUB-BEV', name:'Beverages' },
    ]},
    { id:'CAT-PHARMA', name:'Pharmaceuticals', subs:[
      { id:'SUB-VAX', name:'Vaccines (cold-chain)' },
      { id:'SUB-OTC', name:'OTC Medicines' },
    ]},
    { id:'CAT-HOME',   name:'Household & Care', subs:[
      { id:'SUB-CLEAN', name:'Cleaning' },
      { id:'SUB-PAPER', name:'Paper Goods' },
    ]},
  ],

  // System-level policy (normally edited in Master Data settings).
  // clientAreaSegregation ON: this client requires that different clients' stock is NOT mixed in the same
  // location. With it ON, a client may only be put away into bins whose Area it owns (or an unowned/shared
  // Area); other clients' Areas are refused (binSegregationOk). PRODUCT DEFAULT is OFF (opt-in) — this is a
  // per-deployment config choice, confirmed for this client. See docs/01_Master_Data.md + GLOSSARY.md.
  settings: { clientAreaSegregation: true },

  // ---- Reason codes (MASTER DATA — configurable in erp-md-reasons.html) ----
  // Operational screens never hardcode reasons; they read this via reasonsFor(domain, group).
  // Each domain has a uniform shape { id, label, groupedBy, groups:[{ key, label, reasons:[] }] }
  // so the master screen renders/edits every domain generically. A 'status' domain is keyed by the
  // TARGET status (so the reason list is logically linked to the chosen status — no nonsense pairings).
  reasonDomains: [
    { id:'status', label:'Stock status change', groupedBy:'Target status', groups:[
      { key:'available',  label:'→ Available (release)', reasons:['Inspection passed — release','Hold lifted — release','Re-graded as good','Released by QA','Recount confirmed good'] },
      { key:'quarantine', label:'→ Quarantine',          reasons:['Failed inspection','Recall / quality hold','Suspected contamination','Awaiting QA decision','Pending supplier investigation'] },
      { key:'hold',       label:'→ Hold',                reasons:['Customer / commercial hold','Documentation / paperwork hold','Recall / quality hold','Awaiting QA decision','Legal / customs hold','Awaiting client instruction','Credit / payment hold'] },
      { key:'damaged',    label:'→ Damaged',             reasons:['Damage found','Crushed / broken in handling','Spoilage / temperature excursion','Contaminated'] },
      { key:'expired',    label:'→ Expired',             reasons:['Shelf-life / expiry date passed','Use-by date passed','Failed stability re-test','Short-dated — withdrawn per client'] },
    ]},
    { id:'adjust', label:'Quantity adjustment', groupedBy:'Direction', groups:[
      { key:'increase', label:'Increase (+)', reasons:['Found stock','Count correction (up)','Receiving under-count','Conversion gain'] },
      { key:'decrease', label:'Decrease (−)', reasons:['Loss / shrinkage','Damage write-off','Count correction (down)','Receiving over-count','Sample / destructive test'] },
    ]},
    { id:'correct', label:'Attribute correction', groupedBy:'', groups:[
      { key:'all', label:'All corrections', reasons:['Wrong lot keyed','Wrong expiry keyed','Wrong serial captured','Wrong product','Wrong owning client','Data-entry error'] },
    ]},
    { id:'return', label:'Returns / put-back', groupedBy:'', groups:[
      { key:'all', label:'All returns', reasons:['Customer return — unused','Customer refused delivery','Over-pick put-back','Damaged in transit','Wrong item shipped'] },
    ]},
    // Ad-hoc / emergency dispatch — the JUSTIFICATION for shipping outbound off the normal ERP-order rails
    // (PWA "case 1": no ERP order exists yet). Captured at dispatch + carried on the order for back-office approval.
    { id:'dispatch', label:'Ad-hoc dispatch', groupedBy:'', groups:[
      { key:'all', label:'All ad-hoc dispatches', reasons:['Customer collection — no ERP order','ERP / system unavailable','Emergency / urgent shipment','Phone / email order — key later','Sales order not yet in system'] },
    ]},
  ],

  // (Area affinity + ownership now live on each site's `areas[]` above — see sites.)

  // One row per physical location. Identity = system `id` (scannable, permanent, never changes).
  // `structured` = human-readable code derived from the site's level path. `userRef` = optional free label.
  // `area` = the managed slotting/segregation area the bin belongs to (storage bins only; see site.areas).
  //          Independent of `path` — restructuring the addressing path never changes `area`.
  // Storage bins carry PHYSICAL capacity (maxWeightKg / maxUnits / maxLpns); any unset limit = unlimited.
  // The printed barcode label carries the id (scannable) + the structured code (for humans).
  locations: [
    { id:'LOC-WAIT-01', site:'S-LYON', type:'wait/put',   path:{Zone:'WP'},                                          structured:'WP-01',         userRef:'Inbound staging', status:'active' },
    { id:'LOC-QUAR-01', site:'S-LYON', type:'quarantine', path:{Zone:'QA'},                                          structured:'QA-01',         userRef:'',                status:'active' },
    { id:'LOC-A0101',   site:'S-LYON', type:'storage', area:'A', path:{Floor:'1',Zone:'A',Aisle:'01',Rack:'R1',Bin:'B01'}, structured:'1-A-01-R1-B01', userRef:'',          status:'active', maxWeightKg:500, maxUnits:600, maxLpns:6 },
    { id:'LOC-A0102',   site:'S-LYON', type:'storage', area:'A', path:{Floor:'1',Zone:'A',Aisle:'01',Rack:'R1',Bin:'B02'}, structured:'1-A-01-R1-B02', userRef:'',          status:'active', maxWeightKg:400, maxUnits:500, maxLpns:4 },
    { id:'LOC-A0203',   site:'S-LYON', type:'storage', area:'A', path:{Floor:'1',Zone:'A',Aisle:'02',Rack:'R3',Bin:'B03'}, structured:'1-A-02-R3-B03', userRef:'',          status:'active', maxWeightKg:300, maxUnits:500, maxLpns:4 },
    { id:'LOC-B0101',   site:'S-LYON', type:'storage', area:'B', path:{Floor:'1',Zone:'B',Aisle:'01',Rack:'R1',Bin:'B01'}, structured:'1-B-01-R1-B01', userRef:'',          status:'active', maxWeightKg:600, maxUnits:800, maxLpns:6 },
    { id:'LOC-B0102',   site:'S-LYON', type:'storage', area:'B', path:{Floor:'1',Zone:'B',Aisle:'01',Rack:'R1',Bin:'B02'}, structured:'1-B-01-R1-B02', userRef:'Cold zone', status:'active', maxWeightKg:300, maxUnits:400, maxLpns:4 },
    { id:'LOC-DISP-01', site:'S-LYON', type:'dispatch',   path:{Zone:'D'},                                           structured:'D-01',          userRef:'',                status:'active' },
    { id:'LOC-C0101',   site:'S-PARIS', type:'storage', area:'C', path:{Zone:'C',Aisle:'01'},                              structured:'C-01',          userRef:'',          status:'active', maxWeightKg:400, maxUnits:500, maxLpns:4 },
    { id:'LOC-C0102',   site:'S-PARIS', type:'storage', area:'C', path:{Zone:'C',Aisle:'02'},                              structured:'C-02',          userRef:'',          status:'inactive', maxWeightKg:400, maxUnits:500, maxLpns:4 },
    { id:'LOC-P-WAIT01',site:'S-PARIS', type:'wait/put',  path:{Zone:'WP'},                                          structured:'WP-01',         userRef:'',                status:'active' },
    { id:'LOC-P-DISP01',site:'S-PARIS', type:'dispatch',  path:{Zone:'D'},                                           structured:'D-01',          userRef:'',                status:'active' },
    // TEST stock bins (Area A) — generous capacity so the tracking-flag test stock never collides with the capacity demos.
    { id:'LOC-TC01',    site:'S-LYON', type:'storage', area:'A', path:{Floor:'1',Zone:'A',Aisle:'09',Rack:'R1',Bin:'B01'}, structured:'1-A-09-R1-B01', userRef:'TEST stock bin 1', status:'active', maxWeightKg:5000, maxUnits:5000, maxLpns:50 },
    { id:'LOC-TC02',    site:'S-LYON', type:'storage', area:'A', path:{Floor:'1',Zone:'A',Aisle:'09',Rack:'R1',Bin:'B02'}, structured:'1-A-09-R1-B02', userRef:'TEST stock bin 2', status:'active', maxWeightKg:5000, maxUnits:5000, maxLpns:50 },
  ],
  // products are scoped per client. `weightKg` = unit weight of the BASE unit (for capacity math).
  // `category`/`subCategory` -> taxonomy. `preferred` = optional home storage per site (pre-filtered to the client's sites).
  products: [
    { id: 'P-1001', client: 'C-ACME', sku: 'OLIVE-500', name: 'Olive Oil 500ml',
      uom: 'each', barcode: '5012345000019', track: { lot:true, expiry:true, serial:false },
      category:'CAT-FB', subCategory:'SUB-OIL', weightKg:0.55,
      preferred:[ { site:'S-LYON', mode:'location', ref:'LOC-A0102' } ] },
    { id: 'P-1002', client: 'C-ACME', sku: 'PASTA-1KG', name: 'Pasta Fusilli 1kg',
      uom: 'each', barcode: '5012345000026', track: { lot:false, expiry:false, serial:false },
      category:'CAT-FB', subCategory:'SUB-DRY', weightKg:1.0,
      preferred:[] },
    { id: 'P-2001', client: 'C-GLBX', sku: 'VAX-A',     name: 'Vaccine A (cold-chain)',
      uom: 'vial', barcode: '7612345000033', track: { lot:true, expiry:true, serial:true },
      category:'CAT-PHARMA', subCategory:'SUB-VAX', weightKg:0.02,
      preferred:[ { site:'S-LYON', mode:'area', ref:'B' } ] },
    // ---- TRACKING-FLAG TEST PRODUCTS (one per lot/expiry/serial combination) ----
    // These exist to exercise flag-driven Lot/Expiry/Serial rendering end-to-end (Reception →
    // Putaway → Stock-Out). `testCase` ('A'..'D') surfaces as a "Case X · profile" note in the
    // lists. Case A (no tracking) is the most common real-world case (~90% of SKUs).
    { id: 'P-TCA', client: 'C-ACME', sku: 'TC-A', name: 'Test A — No tracking',
      uom: 'each', barcode: '2000000000017', track: { lot:false, expiry:false, serial:false },
      category:'CAT-FB', subCategory:'SUB-DRY', weightKg:0.30, testCase:'A', preferred:[] },
    { id: 'P-TCB', client: 'C-ACME', sku: 'TC-B', name: 'Test B — Lot only',
      uom: 'each', barcode: '2000000000024', track: { lot:true, expiry:false, serial:false },
      category:'CAT-FB', subCategory:'SUB-DRY', weightKg:0.80, testCase:'B', preferred:[] },
    { id: 'P-TCC', client: 'C-ACME', sku: 'TC-C', name: 'Test C — Lot + Expiry',
      uom: 'each', barcode: '2000000000031', track: { lot:true, expiry:true, serial:false },
      category:'CAT-FB', subCategory:'SUB-DRY', weightKg:0.50, testCase:'C', preferred:[] },
    { id: 'P-TCD', client: 'C-ACME', sku: 'TC-D', name: 'Test D — Lot + Expiry + Serial',
      uom: 'each', barcode: '2000000000048', track: { lot:true, expiry:true, serial:true },
      category:'CAT-FB', subCategory:'SUB-DRY', weightKg:1.20, testCase:'D', preferred:[] },
  ],
  // license plates in various lifecycle states (status drives the badge)
  lpns: [
    { id: 'LPN-00012', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:120, lot:'L240115', expiry:'2026-09-30', serials:[],            status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00013', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:80,  lot:'L240120', expiry:'2027-01-15', serials:[],            status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00021', client:'C-GLBX', site:'S-LYON', product:'P-2001', qty:60,  lot:'VX-92',   expiry:'2026-10-01', serials:['SN-301…360'], status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00008', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:240, lot:'L231201', expiry:'2026-06-30', serials:[],            status:'available', loc:'LOC-A0101' },
    { id: 'LPN-00020', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:470, lot:'L240118', expiry:'2026-10-31', serials:[],            status:'available', loc:'LOC-A0203' },
    // DEMO: physically present + status still 'available' but PAST EXPIRY (today=2026-06-15). Shows the red
    // "expired" tag on Stock Status, is caught by "Select expired", and is excluded from FEFO allocation (isExpired).
    { id: 'LPN-00022', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:90,  lot:'L231010', expiry:'2026-05-20', serials:[],            status:'available', loc:'LOC-A0102' },
    // Pasta has NO lot/expiry/serial tracking — its outbound allocation falls back to FIFO (oldest plate first).
    { id: 'LPN-00016', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:300, lot:'',        expiry:'',           serials:[],            status:'available', loc:'LOC-A0101' },
    { id: 'LPN-00017', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:150, lot:'',        expiry:'',           serials:[],            status:'available', loc:'LOC-A0102' },
    { id: 'LPN-00009', client:'C-GLBX', site:'S-LYON', product:'P-2001', qty:50,  lot:'VX-88',   expiry:'2026-08-01', serials:['SN-001…050'], status:'available', loc:'LOC-B0102' },
    // Already shipped — backs the seeded dispatched order OUT-7000 (Delivery Note demo).
    { id: 'LPN-00007', client:'C-GLBX', site:'S-LYON', product:'P-2001', qty:0,   lot:'VX-80',   expiry:'2026-07-20', serials:['SN-401…440'], status:'dispatched', loc:'LOC-B0102' },
    { id: 'LPN-00005', client:'C-GLBX', site:'S-LYON', product:'P-2001', qty:30,  lot:'VX-71',   expiry:'2026-07-15', serials:['SN-101…130'], status:'quarantine', loc:'LOC-QUAR-01' },
    // held for inspection at receipt (operator flagged "Hold for inspection") — these are the Inspection worklist's Pending items
    { id: 'LPN-00014', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:60,  lot:'L240210', expiry:'2026-07-05', serials:[],              status:'to-inspect', loc:'LOC-WAIT-01' },
    { id: 'LPN-00015', client:'C-GLBX', site:'S-LYON', product:'P-2001', qty:20,  lot:'VX-90',   expiry:'2026-09-01', serials:['SN-201…220'], status:'to-inspect', loc:'LOC-WAIT-01' },
    // In transit on an inter-site transfer (TRF-8001, Luanda→Soyo) — left Luanda, not yet received at Soyo.
    { id: 'LPN-00030', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:100, lot:'',        expiry:'',           serials:[],              status:'in-transit', loc:'LOC-DISP-01' },
    // Repack history (RPK-7000): a 240-unit pasta plate split into two 120s. Source consumed; two outputs available.
    { id: 'LPN-00050', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:0,   lot:'',        expiry:'',           serials:[],              status:'consumed',   loc:'LOC-A0203' },
    { id: 'LPN-00051', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:120, lot:'',        expiry:'',           serials:[],              status:'available',  loc:'LOC-A0203' },
    { id: 'LPN-00052', client:'C-ACME', site:'S-LYON', product:'P-1002', qty:120, lot:'',        expiry:'',           serials:[],              status:'available',  loc:'LOC-A0203' },
    // Restocked by a closed put-back return (RET-9000): 5 olive units returned to stock.
    { id: 'LPN-00060', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:5,   lot:'L231201',  expiry:'2026-06-30', serials:[],              status:'available',  loc:'LOC-A0102' },
    // ---- TRACKING-FLAG TEST STOCK (Cases A–D) ----
    // To-putaway plates (Putaway worklist) — lot/expiry/serials present ONLY where the product's flag is on.
    { id: 'LPN-00101', client:'C-ACME', site:'S-LYON', product:'P-TCA', qty:100, lot:'',          expiry:'',           serials:[],                   status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00102', client:'C-ACME', site:'S-LYON', product:'P-TCB', qty:100, lot:'LOTB-2401', expiry:'',           serials:[],                   status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00103', client:'C-ACME', site:'S-LYON', product:'P-TCC', qty:100, lot:'LOTC-2401', expiry:'2027-03-31', serials:[],                   status:'to-putaway', loc:'LOC-WAIT-01' },
    { id: 'LPN-00104', client:'C-ACME', site:'S-LYON', product:'P-TCD', qty:40,  lot:'LOTD-2401', expiry:'2027-03-31', serials:['SN-TCD-001…040'],   status:'to-putaway', loc:'LOC-WAIT-01' },
    // Available stock (Stock-Out worklist) — held in the dedicated TEST bins.
    { id: 'LPN-00111', client:'C-ACME', site:'S-LYON', product:'P-TCA', qty:200, lot:'',          expiry:'',           serials:[],                   status:'available',  loc:'LOC-TC01' },
    { id: 'LPN-00112', client:'C-ACME', site:'S-LYON', product:'P-TCB', qty:200, lot:'LOTB-2312', expiry:'',           serials:[],                   status:'available',  loc:'LOC-TC01' },
    { id: 'LPN-00113', client:'C-ACME', site:'S-LYON', product:'P-TCC', qty:200, lot:'LOTC-2312', expiry:'2026-12-31', serials:[],                   status:'available',  loc:'LOC-TC02' },
    { id: 'LPN-00114', client:'C-ACME', site:'S-LYON', product:'P-TCD', qty:50,  lot:'LOTD-2312', expiry:'2026-12-31', serials:['SN-TCD-101…150'],   status:'available',  loc:'LOC-TC02' },
  ],
  // inbound advance ship notices
  // `received` = base units already received against the line (across one or more receipts).
  // ASN header status is DERIVED from received vs qty: open -> partial -> closed (see asnStatus()).
  asns: [
    { id: 'ASN-3001', client:'C-ACME', site:'S-LYON', supplier:'SUP-100', lines:[
        { product:'P-1001', qty:120, received:0 }, { product:'P-1002', qty:80, received:0 } ] },
    { id: 'ASN-3002', client:'C-GLBX', site:'S-LYON', supplier:'SUP-200', lines:[
        { product:'P-2001', qty:50, received:30 } ] },
    // ---- TRACKING-FLAG TEST ASNs (one clean single-case inbound per combination; open, ready to receive) ----
    { id: 'ASN-3101', client:'C-ACME', site:'S-LYON', supplier:'SUP-100', lines:[ { product:'P-TCA', qty:100, received:0 } ] },
    { id: 'ASN-3102', client:'C-ACME', site:'S-LYON', supplier:'SUP-100', lines:[ { product:'P-TCB', qty:100, received:0 } ] },
    { id: 'ASN-3103', client:'C-ACME', site:'S-LYON', supplier:'SUP-100', lines:[ { product:'P-TCC', qty:100, received:0 } ] },
    { id: 'ASN-3104', client:'C-ACME', site:'S-LYON', supplier:'SUP-100', lines:[ { product:'P-TCD', qty:40,  received:0 } ] },
  ],
  // outbound requests (orders). Lifecycle: open -> allocated -> picking -> picked -> partial -> dispatched.
  // `ref` = client PO/reference. `fullStockOut` = ship ALL available for each line's product/client/site.
  // Each line: requested `qty`, cumulative `shipped` (base units issued across all shipments), and the
  // CURRENT-round `alloc[]` the Allocation screen fills by FEFO (expiry-tracked) or FIFO (non-expiry).
  //   alloc entry = { lpn, lot, expiry, from(loc), qty(reserved), picked(captured at Pick/Dispatch), serials? }.
  // Allocation reserves stock on the line (alloc[]); the LPN stays `available` with reduced FREE qty
  // (see lpnAvail) and its qty is decremented only when issued at dispatch.
  // REMAINDER POLICY (per client.allowBackorder): a dispatch that ships less than ordered either
  //   - back-orders the remainder (status -> 'partial'; the line re-allocates when stock arrives), or
  //   - short-closes it (status -> 'dispatched'; remainder cancelled, documented on the note).
  // `shipments[]` = immutable history of dispatched batches; each is one Delivery Note.
  // `shipTo` = the CONSIGNEE (a client delivery point in DB.consignees) the order ships to — NOT the client.
  outbound: [
    // Already dispatched (single complete shipment) — seeds the Delivery Note screen (serial appendix demo).
    { id:'OUT-7000', client:'C-GLBX', site:'S-LYON', shipTo:'CNE-GX01', ref:'PO-GX-2210', created:'2026-06-12',
      status:'dispatched', dispatched:'2026-06-13', fullStockOut:false,
      lines:[ { product:'P-2001', qty:40, shipped:40, alloc:[] } ],
      shipments:[ { id:'DN-7000-1', date:'2026-06-13', carrier:'CAR-CCX', lines:[
        { product:'P-2001', picked:40, alloc:[ { lpn:'LPN-00007', lot:'VX-80', expiry:'2026-07-20', from:'LOC-B0102', qty:40, picked:40, serials:'SN-401…440' } ] } ] } ] },
    // FEFO, single earliest-expiry lot fits the request — seeded already allocated.
    { id:'OUT-7001', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-AC-5567', created:'2026-06-15',
      status:'allocated', fullStockOut:false, shipments:[], lines:[
        { product:'P-1001', qty:60, shipped:0, alloc:[
          { lpn:'LPN-00008', lot:'L231201', expiry:'2026-06-30', from:'LOC-A0101', qty:60, picked:0 } ] } ] },
    // Serial-tracked vaccine — FEFO + serial capture at pick; fits.
    { id:'OUT-7002', client:'C-GLBX', site:'S-LYON', shipTo:'CNE-GX01', ref:'PO-GX-2231', created:'2026-06-16',
      status:'open', fullStockOut:false, shipments:[], lines:[
        { product:'P-2001', qty:20, shipped:0, alloc:[] } ] },
    // Non-expiry pasta — FIFO, splits across two plates (300 + 80 of 380).
    { id:'OUT-7003', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC02', ref:'PO-AC-5570', created:'2026-06-16',
      status:'open', fullStockOut:false, shipments:[], lines:[
        { product:'P-1002', qty:380, shipped:0, alloc:[] } ] },
    // ACME (allowBackorder=false): requests 800, only 715 free (LPN-00022's 90 is expired→excluded) → SHORT-CLOSE demo.
    { id:'OUT-7004', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-AC-5571', created:'2026-06-16',
      status:'open', fullStockOut:false, shipments:[], lines:[
        { product:'P-1001', qty:800, shipped:0, alloc:[] } ] },
    // GLBX (allowBackorder=true): requests 70 vaccine, only 50 available → BACK-ORDER demo (20 stays open).
    { id:'OUT-7005', client:'C-GLBX', site:'S-LYON', shipTo:'CNE-GX01', ref:'PO-GX-2240', created:'2026-06-16',
      status:'open', fullStockOut:false, shipments:[], lines:[
        { product:'P-2001', qty:70, shipped:0, alloc:[] } ] },
    // ---- TRACKING-FLAG TEST ORDERS (one open outbound per combination; backed by the TEST available stock above) ----
    { id:'OUT-7101', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-TC-A', created:'2026-06-17',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TCA', qty:120, shipped:0, alloc:[] } ] },
    { id:'OUT-7102', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-TC-B', created:'2026-06-17',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TCB', qty:120, shipped:0, alloc:[] } ] },
    { id:'OUT-7103', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-TC-C', created:'2026-06-17',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TCC', qty:120, shipped:0, alloc:[] } ] },
    { id:'OUT-7104', client:'C-ACME', site:'S-LYON', shipTo:'CNE-AC01', ref:'PO-TC-D', created:'2026-06-17',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TCD', qty:30, shipped:0, alloc:[] } ] },
  ],

  // ---- Inventory adjustments & corrections (Section 05) ----
  // kind:'qty'      -> quantity delta (dir increase|decrease); posting writes lpn.qty.
  // kind:'correct'  -> attribute correction (changes[]); posting writes the LPN's lot/expiry/serial/product/client.
  // Lifecycle: pending -> posted (approved) | rejected. Reasons come from DB.reasonDomains (adjust/correct domains).
  adjustments: [
    { id:'ADJ-5001', kind:'qty', client:'C-ACME', site:'S-LYON', lpn:'LPN-00008', product:'P-1001',
      status:'pending', created:'2026-06-16', by:'Samer Merhi',
      dir:'decrease', reason:'Damage write-off', note:'2 bottles broken in bin', beforeQty:240, delta:2, afterQty:238 },
    { id:'ADJ-5002', kind:'correct', client:'C-ACME', site:'S-LYON', lpn:'LPN-00020', product:'P-1001',
      status:'posted', created:'2026-06-14', by:'Benjamin Felix', posted:'2026-06-14',
      reason:'Wrong expiry keyed', note:'Receipt typo vs CoA', changes:[{ field:'expiry', from:'2026-10-30', to:'2026-10-31' }] },
    { id:'ADJ-5003', kind:'correct', client:'C-ACME', site:'S-LYON', lpn:'LPN-00012', product:'P-1001',
      status:'pending', created:'2026-06-16', by:'Samer Merhi',
      reason:'Wrong lot keyed', note:'Pallet label reads L240116', changes:[{ field:'lot', from:'L240115', to:'L240116' }] },
  ],

  // ---- Stock movements (Section 05) ----
  // Intra-site relocation: location -> location within ONE site. Immediate (no approval); logs a 'move' txn.
  moves: [
    { id:'MOV-6001', site:'S-LYON', lpn:'LPN-00017', product:'P-1002', qty:150, from:'LOC-A0101', to:'LOC-A0102',
      status:'done', date:'2026-06-15', by:'Samer Merhi', note:'Consolidate pasta to aisle 01' },
  ],
  // Inter-site transfer ORDER: header + lines, Site A -> Site B, with an in-transit state.
  // Lifecycle: draft -> in-transit (shipped from A; LPNs -> 'in-transit') -> received (arrived at B; LPNs ->
  // 'available' at the chosen location, site reassigned) | cancelled. Genealogy (lot/expiry/serial) is preserved.
  // A line transfers a full OR partial plate: a partial qty auto-splits at Ship (a child LPN goes
  // in-transit, the remainder stays at the origin) — same model as the intra-site Move on this screen.
  transfers: [
    { id:'TRF-8001', client:'C-ACME', fromSite:'S-LYON', toSite:'S-PARIS', status:'in-transit',
      created:'2026-06-15', shipped:'2026-06-15', received:'', by:'Benjamin Felix',
      lines:[ { lpn:'LPN-00030', product:'P-1002', qty:100, lot:'', expiry:'', serials:[], recvLoc:'' } ] },
    { id:'TRF-8002', client:'C-ACME', fromSite:'S-LYON', toSite:'S-PARIS', status:'draft',
      created:'2026-06-16', shipped:'', received:'', by:'Benjamin Felix',
      lines:[ { lpn:'LPN-00020', product:'P-1001', qty:470, lot:'L240118', expiry:'2026-10-31', serials:[], recvLoc:'' } ] },
  ],

  // ---- Cycle count SHEETS (Section 05) ----
  // A count SHEET spans one OR MANY locations (count many bins in one entry — e.g. transcribing a paper
  // count run — with NO freeze; the frozen full stock-take is Physical Inventory). Each location group
  // carries its own plate lines (counted vs system -> variance). One sheet = one approval decision.
  // Lifecycle: counted -> pending-approval -> approved (stock corrected to counted qty) | rejected (no change).
  // variance = countedQty − systemQty. counted 0 = missing; a line with no system LPN = found stock.
  counts: [
    // pending — two single-location sheets
    { id:'CNT-9001', site:'S-LYON', status:'pending-approval', created:'2026-06-16', countedBy:'Samer Merhi', countedDate:'2026-06-16',
      locations:[ { loc:'LOC-A0101', lines:[ { lpn:'LPN-00008', product:'P-1001', lot:'L231201', systemQty:240, countedQty:238 },
                                             { lpn:'LPN-00016', product:'P-1002', lot:'',        systemQty:300, countedQty:300 } ] } ] },
    { id:'CNT-9002', site:'S-LYON', status:'pending-approval', created:'2026-06-16', countedBy:'Samer Merhi', countedDate:'2026-06-16',
      locations:[ { loc:'LOC-B0102', lines:[ { lpn:'LPN-00009', product:'P-2001', lot:'VX-88', systemQty:50, countedQty:49 } ] } ] },
    // pending — a MULTI-location sheet (3 bins counted in one pass)
    { id:'CNT-9003', site:'S-LYON', status:'pending-approval', created:'2026-06-17', countedBy:'Samer Merhi', countedDate:'2026-06-17',
      locations:[
        { loc:'LOC-A0203', lines:[ { lpn:'LPN-00020', product:'P-1001', lot:'L240118', systemQty:470, countedQty:468 },
                                   { lpn:'LPN-00051', product:'P-1002', lot:'', systemQty:120, countedQty:120 },
                                   { lpn:'LPN-00052', product:'P-1002', lot:'', systemQty:120, countedQty:119 } ] },
        { loc:'LOC-A0102', lines:[ { lpn:'LPN-00017', product:'P-1002', lot:'', systemQty:150, countedQty:150 },
                                   { lpn:'LPN-00060', product:'P-1001', lot:'L231201', systemQty:5, countedQty:5 },
                                   // FOUND stock — 24 pasta units physically present with NO system LPN. Approving mints a new plate.
                                   { lpn:'', found:true, product:'P-1002', lot:'', systemQty:0, countedQty:24 } ] },
      ] },
    // approved (history)
    { id:'CNT-9000', site:'S-LYON', status:'approved', created:'2026-06-14', countedBy:'Benjamin Felix', countedDate:'2026-06-14', approved:'2026-06-14',
      locations:[ { loc:'LOC-A0203', lines:[ { lpn:'LPN-00020', product:'P-1001', lot:'L240118', systemQty:470, countedQty:470 } ] } ] },
  ],

  // ---- Physical inventory / stock-take events (Section 05) ----
  // A freeze-count-reconcile-unfreeze event over a whole SITE or a single Storage AREA.
  // status: open (not yet frozen) -> frozen (counting; scope blocks moves/in/out) -> closed (reconciled + unfrozen).
  // Each in-scope location is counted (per-line counted vs system). Posting corrects stock to the counted figures.
  // FREEZE IS ENFORCED cross-screen (isLocFrozen / frozenTakeFor): while a take is 'frozen', Putaway, Move,
  // Transfer-ship and Allocation REFUSE any location inside its scope. Both seed takes start 'open' (NOT frozen)
  // on purpose — Area A/B hold the shared demo stock, so freezing on load would block the outbound/putaway
  // happy paths. Freeze a take live on erp-inv-physical.html to watch the cross-screen block take effect.
  physicals: [
    { id:'PHY-7001', site:'S-LYON', scope:'area', area:'A', status:'open', frozen:false, created:'2026-06-16', by:'Benjamin Felix', locations:[
        { loc:'LOC-A0101', status:'counted', lines:[ { lpn:'LPN-00008', product:'P-1001', systemQty:240, countedQty:238 }, { lpn:'LPN-00016', product:'P-1002', systemQty:300, countedQty:300 } ] },
        { loc:'LOC-A0102', status:'pending', lines:[ { lpn:'LPN-00017', product:'P-1002', systemQty:150, countedQty:null } ] },
        { loc:'LOC-A0203', status:'pending', lines:[ { lpn:'LPN-00020', product:'P-1001', systemQty:470, countedQty:null } ] },
      ] },
    { id:'PHY-7002', site:'S-LYON', scope:'area', area:'B', status:'open', frozen:false, created:'2026-06-16', by:'Benjamin Felix', locations:[
        { loc:'LOC-B0101', status:'pending', lines:[] },
        { loc:'LOC-B0102', status:'pending', lines:[ { lpn:'LPN-00009', product:'P-2001', systemQty:50, countedQty:null } ] },
      ] },
    { id:'PHY-7000', site:'S-PARIS', scope:'site', area:'', status:'closed', frozen:false, created:'2026-06-10', closed:'2026-06-10', by:'Nicolas Masserey', locations:[
        { loc:'LOC-C0101', status:'counted', lines:[] } ] },
  ],

  // ---- Repack / Split / Merge / Re-kit jobs (Section 05) ----
  // Source plate(s) are CONSUMED; output plate(s) are CREATED, carrying lot/expiry/serial genealogy.
  //   split  : 1 source -> N outputs (same product/lot); source reduced by the total, fully consumed if 0.
  //   merge  : N sources (same product+lot+expiry) -> 1 output (summed); sources consumed.
  //   repack : 1 source -> 1 output, same qty/genealogy, new packaging label.
  //   rekit  : assemble/disassemble — source(s) consumed, freely-defined output(s) created.
  repacks: [
    { id:'RPK-7000', kind:'split', site:'S-LYON', status:'confirmed', created:'2026-06-14', by:'Samer Merhi',
      sources:[ { lpn:'LPN-00050', product:'P-1002', qty:240 } ],
      outputs:[ { lpn:'LPN-00051', product:'P-1002', qty:120, lot:'', expiry:'', loc:'LOC-A0203', note:'' },
                { lpn:'LPN-00052', product:'P-1002', qty:120, lot:'', expiry:'', loc:'LOC-A0203', note:'' } ] },
  ],

  // ---- Returns / put-back (Section 05) ----
  // Stock RE-ENTERING inventory: kind 'putback' (over-picked / unused stock back to a bin) or
  // 'customer' (post-dispatch return → re-inspect). Per line a disposition routes it: restock (→ available),
  // quarantine or damaged (blocked). Processing creates the LPN(s) and logs a 'return' txn. ref → source order.
  returns: [
    { id:'RET-9000', kind:'putback', client:'C-ACME', site:'S-LYON', ref:'OUT-7001', status:'closed', created:'2026-06-15', closed:'2026-06-15', by:'Samer Merhi',
      lines:[ { product:'P-1001', qty:5, lot:'L231201', expiry:'2026-06-30', serials:[], reason:'Over-pick put-back', disposition:'restock', toLoc:'LOC-A0102', lpn:'LPN-00060' } ] },
    { id:'RET-9001', kind:'customer', client:'C-GLBX', site:'S-LYON', ref:'OUT-7000', status:'open', created:'2026-06-16', by:'Samer Merhi',
      lines:[ { product:'P-2001', qty:10, lot:'VX-80', expiry:'2026-07-20', serials:['SN-431…440'], reason:'Customer return — unused', disposition:'', toLoc:'', lpn:'' } ] },
    { id:'RET-9002', kind:'putback', client:'C-ACME', site:'S-LYON', ref:'', status:'open', created:'2026-06-16', by:'Samer Merhi',
      lines:[ { product:'P-1002', qty:20, lot:'', expiry:'', serials:[], reason:'Over-pick put-back', disposition:'', toLoc:'', lpn:'' } ] },
  ],

  // ---- Units of measure (base + packaging units), grouped by category ----
  uoms: [
    // count
    { code:'EA',   name:'Each',               cat:'Count',     dec:false, base:true },
    { code:'PC',   name:'Piece',              cat:'Count',     dec:false },
    { code:'PR',   name:'Pair',               cat:'Count',     dec:false },
    { code:'DZ',   name:'Dozen (12)',         cat:'Count',     dec:false },
    { code:'VIAL', name:'Vial',               cat:'Count',     dec:false },
    // weight
    { code:'KG',   name:'Kilogram',           cat:'Weight',    dec:true, base:true },
    { code:'G',    name:'Gram',               cat:'Weight',    dec:true },
    { code:'T',    name:'Tonne',              cat:'Weight',    dec:true },
    { code:'LB',   name:'Pound',              cat:'Weight',    dec:true },
    // volume
    { code:'L',    name:'Litre',              cat:'Volume',    dec:true, base:true },
    { code:'ML',   name:'Millilitre',         cat:'Volume',    dec:true },
    { code:'CL',   name:'Centilitre',         cat:'Volume',    dec:true },
    // length
    { code:'M',    name:'Metre',              cat:'Length',    dec:true, base:true },
    { code:'CM',   name:'Centimetre',         cat:'Length',    dec:true },
    // packaging / handling units
    { code:'6PK',  name:'Six-pack (6)',       cat:'Packaging', dec:false },
    { code:'INR',  name:'Inner pack',         cat:'Packaging', dec:false },
    { code:'BX6',  name:'Box of 6',           cat:'Packaging', dec:false },
    { code:'BX12', name:'Box of 12 (dozen)',  cat:'Packaging', dec:false },
    { code:'BX24', name:'Box of 24',          cat:'Packaging', dec:false },
    { code:'BX',   name:'Box (generic)',      cat:'Packaging', dec:false },
    { code:'CTN',  name:'Carton',             cat:'Packaging', dec:false },
    { code:'CS',   name:'Case',               cat:'Packaging', dec:false },
    { code:'TRY',  name:'Tray',               cat:'Packaging', dec:false },
    { code:'BDL',  name:'Bundle',             cat:'Packaging', dec:false },
    { code:'LYR',  name:'Layer',              cat:'Packaging', dec:false },
    { code:'PAL',  name:'Pallet',             cat:'Packaging', dec:false },
    { code:'BAG',  name:'Bag',                cat:'Packaging', dec:false },
    { code:'SCH',  name:'Sachet',             cat:'Packaging', dec:false },
    { code:'BTL',  name:'Bottle',             cat:'Packaging', dec:false },
    { code:'DRM',  name:'Drum',               cat:'Packaging', dec:false },
    { code:'ROL',  name:'Roll',               cat:'Packaging', dec:false },
  ],

  // ---- Packaging hierarchies (each level: qty in its parent + cumulative factor to base) ----
  // `shared:true` = global template (no client/product); clone onto a product to add its barcodes.
  packagings: [
    { id:'PKG-T-DOZEN', name:'Dozen (Each → Dozen)', shared:true, client:'—', product:'—', base:'Each', levels:[
      { level:'Each',  uom:'EA', perParent:1,  factor:1,  barcode:'—', note:'base unit' },
      { level:'Dozen', uom:'DZ', perParent:12, factor:12, barcode:'—', note:'12 × each' },
    ]},
    { id:'PKG-T-SIX', name:'Six-pack (Each → Six-pack)', shared:true, client:'—', product:'—', base:'Each', levels:[
      { level:'Each',     uom:'EA',  perParent:1, factor:1, barcode:'—', note:'base unit' },
      { level:'Six-pack', uom:'6PK', perParent:6, factor:6, barcode:'—', note:'6 × each' },
    ]},
    { id:'PKG-T-RETAIL', name:'Standard retail (Each → Six-pack → Dozen → Carton → Pallet)', shared:true, client:'—', product:'—', base:'Each', levels:[
      { level:'Each',              uom:'EA',   perParent:1,  factor:1,    barcode:'—', note:'base unit' },
      { level:'Six-pack',          uom:'6PK',  perParent:6,  factor:6,    barcode:'—', note:'6 × each' },
      { level:'Box of 12 (dozen)', uom:'BX12', perParent:2,  factor:12,   barcode:'—', note:'2 × six-pack' },
      { level:'Carton',            uom:'CTN',  perParent:6,  factor:72,   barcode:'—', note:'6 × dozen' },
      { level:'Pallet',            uom:'PAL',  perParent:40, factor:2880, barcode:'—', note:'40 cartons' },
    ]},
    { id:'PKG-T-CARTON', name:'Carton & pallet (Each → Carton → Pallet)', shared:true, client:'—', product:'—', base:'Each', levels:[
      { level:'Each',   uom:'EA',  perParent:1,  factor:1,   barcode:'—', note:'base unit' },
      { level:'Carton', uom:'CTN', perParent:24, factor:24,  barcode:'—', note:'24 × each' },
      { level:'Pallet', uom:'PAL', perParent:40, factor:960, barcode:'—', note:'40 cartons' },
    ]},
    { id:'PKG-T-PARALLEL', name:'Parallel packs (6 / 12 / 14, each off base)', shared:true, client:'—', product:'—', base:'Each', levels:[
      { level:'Each',        uom:'EA',   perParent:1,  factor:1,  barcode:'—', note:'base unit' },
      { level:'Pack of 6',   uom:'BX6',  basis:'base', perParent:6,  factor:6,  barcode:'—', note:'6 × each (independent)' },
      { level:'Pack of 12',  uom:'BX12', basis:'base', perParent:12, factor:12, barcode:'—', note:'12 × each (independent)' },
      { level:'Pack of 14',  uom:'BX',   basis:'base', perParent:14, factor:14, barcode:'—', note:'14 × each (independent, non-nesting)' },
    ]},
    { id:'PKG-OLIVE', name:'Olive Oil 500ml — retail', client:'C-ACME', product:'P-1001', base:'Each (bottle)', levels:[
      { level:'Each',              uom:'EA',   perParent:1,  factor:1,    barcode:'5012345000019',  note:'Consumer unit' },
      { level:'Six-pack',          uom:'6PK',  perParent:6,  factor:6,    barcode:'25012345000016', note:'6 × each' },
      { level:'Box of 12 (dozen)', uom:'BX12', perParent:2,  factor:12,   barcode:'15012345000019', note:'2 × six-pack' },
      { level:'Carton',            uom:'CTN',  perParent:6,  factor:72,   barcode:'35012345000013', note:'6 × dozen' },
      { level:'Pallet',            uom:'PAL',  perParent:40, factor:2880, barcode:'—',              note:'40 cartons (8 per layer × 5 layers)' },
    ]},
    { id:'PKG-PASTA', name:'Pasta Fusilli 1kg', client:'C-ACME', product:'P-1002', base:'Each (1 kg bag)', levels:[
      { level:'Each',           uom:'EA',   perParent:1,  factor:1,   barcode:'5012345000026',  note:'1 kg bag' },
      { level:'Inner of 6',     uom:'BX6',  perParent:6,  factor:6,   barcode:'25012345000023', note:'6 × each' },
      { level:'Carton of 12',   uom:'BX12', perParent:2,  factor:12,  barcode:'15012345000026', note:'2 × inner' },
      { level:'Layer',          uom:'LYR',  perParent:10, factor:120, barcode:'—',              note:'10 cartons' },
      { level:'Pallet',         uom:'PAL',  perParent:6,  factor:720, barcode:'—',              note:'6 layers' },
    ]},
    { id:'PKG-VAX', name:'Vaccine A — cold chain', client:'C-GLBX', product:'P-2001', base:'Vial', levels:[
      { level:'Vial',             uom:'VIAL', perParent:1,  factor:1,    barcode:'7612345000033',  note:'Serial-tracked' },
      { level:'Blister of 10',    uom:'INR',  perParent:10, factor:10,   barcode:'27612345000030', note:'10 vials' },
      { level:'Inner box of 50',  uom:'BX',   perParent:5,  factor:50,   barcode:'17612345000033', note:'5 blisters' },
      { level:'Carton of 200',    uom:'CTN',  perParent:4,  factor:200,  barcode:'37612345000037', note:'4 inner boxes' },
      { level:'Insulated pallet', uom:'PAL',  perParent:24, factor:4800, barcode:'—',              note:'24 cartons · 2–8 °C' },
    ]},
    { id:'PKG-BOXES', name:'Multi-size box demo', client:'C-ACME', product:'—', base:'Each', levels:[
      { level:'Each',              uom:'EA',   perParent:1,  factor:1,   barcode:'—', note:'base unit' },
      { level:'Box of 6',          uom:'BX6',  perParent:6,  factor:6,   barcode:'—', note:'half-dozen' },
      { level:'Box of 12 (dozen)', uom:'BX12', perParent:2,  factor:12,  barcode:'—', note:'1 dozen' },
      { level:'Box of 24',         uom:'BX24', perParent:2,  factor:24,  barcode:'—', note:'2 dozen' },
      { level:'Case of 48',        uom:'CS',   perParent:2,  factor:48,  barcode:'—', note:'4 dozen' },
      { level:'Pallet',            uom:'PAL',  perParent:20, factor:960, barcode:'—', note:'20 cases' },
    ]},
  ],

  // ---- Users / roles (scoped by site and/or client) ----
  // allClients + clientIds drive the Client–User Mapping screen (erp-md-clientmap.html): which clients' stock
  // a user may access. allClients:true ⇒ every client (clientIds ignored). The `clients` string is the human
  // label kept in sync for the Users & Roles list. firstName/lastName/username feed the mapping grid columns.
  users: [
    { id:'U-001', name:'Alice Bernard', firstName:'Alice', lastName:'Bernard', username:'abernard', email:'alice@op.example', role:'Administrator', sites:'All sites',  clients:'All clients',    allClients:true,  clientIds:[],         status:'active' },
    { id:'U-002', name:'Benjamin Felix',  firstName:'Benjamin', lastName:'Felix',  username:'bfelix',  email:'benjamin@op.example', role:'Supervisor',    sites:'Luanda',     clients:'All clients',    allClients:true,  clientIds:[],         status:'active' },
    { id:'U-003', name:'Samer Merhi',  firstName:'Samer',  lastName:'Merhi', username:'smerhi', email:'samer@op.example',  role:'Operator',      sites:'Luanda',     clients:'ACME Foods Ltd', allClients:false, clientIds:['C-ACME'], status:'active' },
    { id:'U-004', name:'Nicolas Masserey',     firstName:'Nicolas',   lastName:'Masserey',   username:'nmasserey',   email:'nicolas@op.example',   role:'Operator',      sites:'Soyo',       clients:'Globex Pharma',  allClients:false, clientIds:['C-GLBX'], status:'active' },
    { id:'U-005', name:'Sara Conti',    firstName:'Sara',  lastName:'Conti',   username:'sconti',   email:'sara@op.example',  role:'Operator',      sites:'All sites',  clients:'All clients',    allClients:true,  clientIds:[],         status:'inactive' },
  ],

  // ---- Transaction history / audit (Section 06 reads this; every inventory op appends here via logTxn) ----
  // Minimal seed of prior events so Reports has data to show. type ∈ receive|putaway|move|transfer-ship|
  // transfer-receive|adjust|correct|count|status|repack|return|dispatch.
  txns: [
    { id:'TXN-1001', ts:'2026-06-10 09:12', type:'receive',  lpn:'LPN-00008', product:'P-1001', qty:240, from:'',            to:'LOC-WAIT-01', site:'S-LYON', user:'Samer Merhi', ref:'GRN-4001', note:'Goods received' },
    { id:'TXN-1002', ts:'2026-06-10 11:40', type:'putaway',  lpn:'LPN-00008', product:'P-1001', qty:240, from:'LOC-WAIT-01', to:'LOC-A0101',   site:'S-LYON', user:'Samer Merhi', ref:'',         note:'Directed putaway (home)' },
    { id:'TXN-1003', ts:'2026-06-13 14:05', type:'dispatch', lpn:'LPN-00007', product:'P-2001', qty:40,  from:'LOC-B0102',   to:'',            site:'S-LYON', user:'Benjamin Felix', ref:'OUT-7000', note:'Dispatched · DN-7000-1' },
  ],
};

/* tiny helpers used by screens */
function dbName(coll, id, key='name'){ const r=(DB[coll]||[]).find(x=>x.id===id); return r?r[key]:id; }
function prodName(id){ const p=DB.products.find(x=>x.id===id); return p?`${p.name} (${p.sku})`:id; }
function catName(id){ const c=(DB.categories||[]).find(x=>x.id===id); return c?c.name:(id||'—'); }
function subCatName(id){ for(const c of (DB.categories||[])){ const s=(c.subs||[]).find(x=>x.id===id); if(s) return s.name; } return id||'—'; }
function unitWeight(id){ const p=DB.products.find(x=>x.id===id); return (p&&p.weightKg)||0; }
/* ---- Product tracking flags (lot/expiry/serial) — the single source of truth for flag-driven
        show/hide of Lot, Expiry and Serial fields + columns on EVERY screen (ERP + PWA).
        A field/column for a tracking attribute renders ONLY when the product's flag is on. ---- */
function prodTrack(id){ const p=DB.products.find(x=>x.id===id); return (p&&p.track)||{lot:false,expiry:false,serial:false}; }
function tracksLot(id){ return !!prodTrack(id).lot; }
function tracksExpiry(id){ return !!prodTrack(id).expiry; }
function tracksSerial(id){ return !!prodTrack(id).serial; }
// Short human summary of a product's tracking profile (used for list "case" notes / captions).
function trackingSummary(id){ const t=prodTrack(id), on=[]; if(t.lot)on.push('Lot'); if(t.expiry)on.push('Expiry'); if(t.serial)on.push('Serial'); return on.length?on.join(' + '):'No tracking'; }
// Test-case tag (A..D) for the flag-combination demo products; '' for ordinary products.
function testCaseOf(id){ const p=DB.products.find(x=>x.id===id); return (p&&p.testCase)||''; }
// Grid badge for a product's test case, e.g. "Case A · No tracking" ('' when not a test product).
function testCaseNote(id){ const c=testCaseOf(id); return c?`Case ${c} · ${trackingSummary(id)}`:''; }
// Case note for a DOCUMENT whose lines reference products (ASN / outbound order) — returns the single
// shared test-case badge, or '' when no line is a test product / lines span more than one case.
function docCaseNote(lines){
  const cs=[...new Set((lines||[]).map(l=>testCaseOf(l.product)).filter(Boolean))];
  if(cs.length!==1) return '';
  const ln=(lines||[]).find(l=>testCaseOf(l.product)); return ln?testCaseNote(ln.product):'';
}
function siteAreas(siteId){ const s=DB.sites.find(x=>x.id===siteId); return (s&&s.areas)||[]; }
function areaInfo(siteId, code){ return siteAreas(siteId).find(z=>z.code===code) || null; }
function statusBadge(s){
  const map={'to-putaway':'b-toputaway','to-inspect':'b-allocated','available':'b-available','allocated':'b-allocated','picked':'b-picked',
    'dispatched':'b-dispatched','in-transit':'b-intransit','hold':'b-hold','quarantine':'b-quarantine','damaged':'b-damaged','expired':'b-damaged',
    'consumed':'b-dispatched','partial':'b-toputaway','closed':'b-available','cancelled':'b-cancelled',
    'disposed':'b-dispatched','lost':'b-cancelled','refused':'b-cancelled'};
  return `<span class="badge ${map[s]||''}">${s}</span>`;
}

/* ---- ASN receipt progress (derived from line.received vs line.qty) ---- */
function asnTotals(a){
  const exp = a.lines.reduce((s,l)=>s+(l.qty||0),0);
  const rec = a.lines.reduce((s,l)=>s+(l.received||0),0);
  const linesComplete = a.lines.filter(l=>(l.received||0) >= l.qty).length;
  return { exp, rec, linesComplete, lines: a.lines.length };
}
function asnStatus(a){
  if (a.state==='cancelled' || a.state==='refused') return a.state;   // explicit lifecycle override (void / refuse-delivery)
  const t = asnTotals(a);
  if (t.rec <= 0) return 'open';
  if (a.lines.every(l=>(l.received||0) >= l.qty)) return 'closed';
  return 'partial';
}

/* ---- Outbound allocation helpers (FEFO / FIFO, reservation-aware) ---- */
// Base units of an LPN already reserved by OTHER live (un-dispatched) orders.
function outReserved(lpnId, exceptOrderId){
  let r = 0;
  (DB.outbound||[]).forEach(o => {
    if (o.id === exceptOrderId) return;
    if (!['allocated','picking','picked'].includes(o.status)) return;
    (o.lines||[]).forEach(ln => (ln.alloc||[]).forEach(a => { if (a.lpn === lpnId) r += (a.qty||0); }));
  });
  return r;
}
// Free (allocatable) base units left on an LPN, after other orders' reservations.
function lpnAvail(lpnId, exceptOrderId){
  const l = DB.lpns.find(x => x.id === lpnId);
  if (!l) return 0;
  return Math.max(0, l.qty - outReserved(lpnId, exceptOrderId));
}
// Candidate LPNs for an outbound line, ordered FEFO (expiry-tracked) or FIFO (else, oldest plate by id).
// Returns { usesExpiry, list } where list excludes anything with zero free qty.
function outboundCandidates(product, client, site, exceptOrderId){
  const p = DB.products.find(x => x.id === product) || {};
  const usesExpiry = !!(p.track && p.track.expiry);
  const list = DB.lpns
    .filter(l => l.product===product && l.client===client && l.site===site &&
                 l.status==='available' && !isExpired(l) && !isLocFrozen(l.loc) && lpnAvail(l.id, exceptOrderId) > 0)
    .sort(usesExpiry
      ? (a,b) => String(a.expiry||'9999-12-31').localeCompare(String(b.expiry||'9999-12-31')) || a.id.localeCompare(b.id)
      : (a,b) => a.id.localeCompare(b.id));
  return { usesExpiry, list };
}
// Greedy FEFO/FIFO fill of `need` base units; honours `fullStockOut` (take everything available).
// Returns { alloc:[{lpn,lot,expiry,from,qty,picked}], allocated, requested, short, usesExpiry }.
function fefoAllocate(line, order){
  const { usesExpiry, list } = outboundCandidates(line.product, order.client, order.site, order.id);
  const full = !!order.fullStockOut;
  let need = full ? Infinity : (line.qty||0);
  const alloc = []; let allocated = 0;
  for (const l of list){
    if (need <= 0) break;
    const free = lpnAvail(l.id, order.id);
    const take = full ? free : Math.min(free, need);
    if (take <= 0) continue;
    alloc.push({ lpn:l.id, lot:l.lot||'', expiry:l.expiry||'', from:l.loc, qty:take, picked:0 });
    allocated += take; if (!full) need -= take;
  }
  const requested = full ? allocated : (line.qty||0);
  return { alloc, allocated, requested, short: Math.max(0, requested - allocated), usesExpiry };
}
// Order rollup across lines: requested / allocated / picked / shipped totals + flags.
// `shipped` is cumulative (across all dispatches); `remaining` = ordered − shipped (still owed).
function outTotals(o){
  let req=0, allc=0, pick=0, ship=0; let short=false;
  (o.lines||[]).forEach(ln => {
    if (ln.cancelled) return;   // a cancelled line is excluded from the order's totals
    const r = o.fullStockOut ? (ln.alloc||[]).reduce((s,a)=>s+a.qty,0) : (ln.qty||0);
    const a = (ln.alloc||[]).reduce((s,x)=>s+(x.qty||0),0);
    const pk = (ln.alloc||[]).reduce((s,x)=>s+(x.picked||0),0);
    req+=r; allc+=a; pick+=pk; ship+=(ln.shipped||0); if (a < r) short = true;
  });
  const remaining = Math.max(0, req - ship);
  return { lines:(o.lines||[]).length, req, allc, pick, ship, remaining, short };
}
// Per-line cumulative shipped + remaining-to-fulfil (ordered − shipped).
function lineShipped(line){ return line.shipped || 0; }
function lineRemaining(line){ return Math.max(0, (line.qty||0) - lineShipped(line)); }
// True once every (non-cancelled) line has shipped its full ordered qty.
function outboundComplete(o){ return (o.lines||[]).every(ln => ln.cancelled || lineShipped(ln) >= (ln.qty||0)); }
// Remainder policy for an order's client: true = back-order the shortfall, false = short-close it.
function clientAllowsBackorder(clientId){ const c=DB.clients.find(x=>x.id===clientId); return !!(c && c.allowBackorder); }

/* ============================================================
   Inventory Operations helpers (Section 05)
   Stock-on-hand is DERIVED from LPNs — no balances table.
   ============================================================ */
// Statuses that block outbound allocation (physically present but not shippable).
const BLOCKED_STATUSES = ['quarantine','hold','damaged','expired'];
function isBlocked(s){ return BLOCKED_STATUSES.includes(s); }
// "Today" is mocked for expiry math (see CLAUDE.md). A plate is expired if it carries an
// expiry date already in the past — expired stock is physically present but must NOT ship,
// even while its status is still 'available' (until someone blocks it on Stock Status).
const WMS_TODAY = '2026-06-15';
function isExpired(l){ return !!(l && l.expiry) && String(l.expiry) < WMS_TODAY; }
// A plate is allocatable iff it is 'available', NOT past-expiry, and has free (un-reserved) qty.
function isAllocatable(l){ return !!l && l.status==='available' && !isExpired(l) && lpnAvail(l.id) > 0; }
function lpnById(id){ return DB.lpns.find(x=>x.id===id) || null; }
// Human location code (structured) for a location id; falls back to the id.
function locName(id){ const l=DB.locations.find(x=>x.id===id); return l ? (l.structured||l.id) : (id||'—'); }
// Physically-present plates (qty>0) at a site, any status. Pass site='' for all sites.
function onHandLpns(site){ return DB.lpns.filter(l => (l.qty||0)>0 && (!site || l.site===site)); }

/* ---- Shared bin capacity + client–area segregation (single source of truth; used by Putaway
        directed-slotting AND Returns direct-restock, so the two paths can never diverge) ---- */
// Physical occupancy of a bin — blocked stock still takes space; in-transit has physically left.
function binLoad(binId){
  let units=0, weight=0, lpns=0;
  DB.lpns.filter(l=>l.loc===binId && (l.qty||0)>0 && l.status!=='in-transit')
    .forEach(l=>{ units+=l.qty; weight+=l.qty*unitWeight(l.product); lpns++; });
  return { units, weight:+weight.toFixed(2), lpns };
}
// Would adding one plate of (qty, product) to binId fit? → { ok, fails:[{dim,after,limit}], after }.
function binCapacityForAdd(binId, qty, product){
  const bin=DB.locations.find(x=>x.id===binId)||{}, pl=binLoad(binId);
  const addW=+(((qty||0))*unitWeight(product)).toFixed(2);
  const after={ units:pl.units+(qty||0), weight:+(pl.weight+addW).toFixed(1), lpns:pl.lpns+1 };
  const fails=[];
  if(bin.maxUnits   !=null && after.units >bin.maxUnits)   fails.push({dim:'units',after:after.units, limit:bin.maxUnits});
  if(bin.maxWeightKg!=null && after.weight>bin.maxWeightKg)fails.push({dim:'kg',   after:after.weight,limit:bin.maxWeightKg});
  if(bin.maxLpns    !=null && after.lpns  >bin.maxLpns)    fails.push({dim:'slots',after:after.lpns,  limit:bin.maxLpns});
  return { ok:fails.length===0, fails, after };
}
// Client–area segregation: when settings.clientAreaSegregation is ON, an owned Area accepts only its owner.
function binSegregationOk(binId, client){
  if(!(DB.settings && DB.settings.clientAreaSegregation)) return true;
  const bin=DB.locations.find(x=>x.id===binId)||{}; const zp=areaInfo(bin.site, bin.area); const owner=zp&&zp.owningClient;
  return !owner || owner===client;
}

/* ---- Physical-inventory FREEZE enforcement (shared; read by Putaway, Move, Transfer-ship + Allocation) ----
   A location inside an active FROZEN stock-take is locked: no putaway, move, transfer-ship, adjustment or
   allocation may touch it until the take is posted/abandoned (unfrozen). Only the 'frozen' state locks —
   'open' and 'closed' takes leave stock fully movable (identical movement impact). Returns the locking
   PHY-… take (so screens can name it in the refusal message) or null. */
function frozenTakeFor(locId){
  return (DB.physicals||[]).find(p => (p.status==='frozen' || p.frozen) &&
    (p.locations||[]).some(L => L.loc===locId)) || null;
}
function isLocFrozen(locId){ return !!frozenTakeFor(locId); }

/* ---- Consignees / ship-to lookup (client-scoped delivery points; outbound ships HERE, not to the client) ---- */
function consigneesFor(clientId){ return (DB.consignees||[]).filter(c=>c.client===clientId && c.status!=='inactive'); }
function consigneeName(id){ const c=(DB.consignees||[]).find(x=>x.id===id); return c?c.name:(id||'—'); }
// Client–User mapping helpers (erp-md-clientmap.html). userClientNames → resolved client names for a user's
// clientIds; userClientsLabel → 'All clients' / comma-list / '— none —' label (also used to refresh user.clients).
function userClientNames(u){ return (u && Array.isArray(u.clientIds) ? u.clientIds : []).map(id => dbName('clients', id)); }
function userClientsLabel(u){ if(!u) return '—'; if(u.allClients) return 'All clients'; const ns=userClientNames(u); return ns.length ? ns.join(', ') : '— none —'; }
// Append an audit row (session-only in the mock). Auto-stamps id + timestamp.
let _txnSeq = 1900;
function nowStamp(){ const d=new Date(), p=n=>String(n).padStart(2,'0');
  return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`; }
function logTxn(t){ const row = Object.assign({ id:'TXN-'+(++_txnSeq), ts:nowStamp() }, t);
  (DB.txns = DB.txns || []).push(row); return row; }
// Mint the next LPN id (e.g. for repack/split outputs). Pads to the existing 5-digit style.
function nextLpnId(){ let n=0; DB.lpns.forEach(l=>{ const m=/LPN-(\d+)/.exec(l.id); if(m) n=Math.max(n,+m[1]); }); return 'LPN-'+String(n+1).padStart(5,'0'); }
// Mint the next outbound-order id (e.g. for a PWA ad-hoc dispatch that originates an order on the floor).
function nextOutId(){ let n=0; (DB.outbound||[]).forEach(o=>{ const m=/OUT-(\d+)/.exec(o.id); if(m) n=Math.max(n,+m[1]); }); return 'OUT-'+String(n+1).padStart(4,'0'); }

/* ---- Reason codes (master-data driven; see DB.reasonDomains) ---- */
function reasonDomain(id){ return (DB.reasonDomains||[]).find(d=>d.id===id) || null; }
function reasonGroup(domainId, groupKey){
  const d = reasonDomain(domainId); if (!d) return null;
  if (!groupKey && d.groups.length===1) return d.groups[0];
  return d.groups.find(g=>g.key===groupKey) || null;
}
// The configured reason list for a domain (+ group, e.g. a target status or 'increase'/'decrease').
// Domains with a single group ignore groupKey. Returns a fresh array.
function reasonsFor(domainId, groupKey){ const g = reasonGroup(domainId, groupKey); return g ? g.reasons.slice() : []; }
function addReason(domainId, groupKey, text){
  const g = reasonGroup(domainId, groupKey); const t=(text||'').trim();
  if (!g || !t || g.reasons.includes(t)) return false; g.reasons.push(t); return true;
}
function removeReason(domainId, groupKey, text){
  const g = reasonGroup(domainId, groupKey); if (!g) return false;
  const i = g.reasons.indexOf(text); if (i<0) return false; g.reasons.splice(i,1); return true;
}

/* ============================================================
   PWA SCAN RESOLUTION (shared; consumed by assets/pwa-scan.js)
   Maps a scanned / typed code to a domain entity. The id and
   barcode namespaces don't overlap (LPN-/LOC-/OUT-/ASN- ids,
   human structured bin codes, EAN/GS1 product barcodes, SKUs,
   client PO refs) so a single best-match by priority is safe.
   Matching is case-insensitive + whitespace-trimmed.
     resolveScan(code) -> { code, type, id, entity, label, sub, extra } | null
       type ∈ 'lpn' | 'location' | 'product' | 'order' | 'asn'
   For a product matched on a packaging-level barcode, extra.level
   is that level (lets Receive default the pack level + factor).
   ============================================================ */
function prodUom(id){ const p=DB.products.find(x=>x.id===id); return p?p.uom:''; }
function packagingFor(productId){ const k=DB.packagings.find(x=>x.product===productId); return k?(k.levels||[]):[]; }
// Physically-present plates (qty>0) at a location.
function lpnsAtLoc(locId){ return DB.lpns.filter(l=>l.loc===locId && (l.qty||0)>0); }
// Physically-present plates (qty>0) of a product, optionally scoped to a site.
function lpnsOfProductAtSite(productId, site){ return DB.lpns.filter(l=>l.product===productId && (l.qty||0)>0 && (!site||l.site===site)); }

function resolveScan(raw){
  const code = String(raw==null?'':raw).trim();
  if (!code) return null;
  const U = code.toUpperCase();

  // 1) LPN (license plate) — exact id
  const lpn = DB.lpns.find(l => l.id.toUpperCase() === U);
  if (lpn) return { code, type:'lpn', id:lpn.id, entity:lpn,
    label:lpn.id, sub:`${prodName(lpn.product)} · ${lpn.qty} ${prodUom(lpn.product)}`, extra:{} };

  // 1b) Pallet — mixed (aggregate) receiving handling unit, exact id
  const plt = (DB.pallets||[]).find(p => p.id.toUpperCase() === U);
  if (plt){ const t = palletTotals(plt); return { code, type:'pallet', id:plt.id, entity:plt,
    label:plt.id, sub:`mixed pallet · ${t.lines} line(s) · ${t.units} units`, extra:{} }; }

  // 2) Location — system id OR human structured code OR user reference
  const loc = DB.locations.find(l => l.id.toUpperCase() === U
    || String(l.structured||'').toUpperCase() === U
    || (l.userRef && l.userRef.toUpperCase() === U));
  if (loc) return { code, type:'location', id:loc.id, entity:loc,
    label:loc.structured||loc.id, sub:`${dbName('sites',loc.site)} · ${loc.type}`, extra:{} };

  // 3) Product — a packaging-level barcode, the product.barcode, or the SKU
  for (const p of DB.products){
    const lvl = packagingFor(p.id).find(L => L.barcode && L.barcode!=='—' && L.barcode.toUpperCase()===U);
    const byBarcode = !!lvl || (p.barcode && p.barcode.toUpperCase()===U);
    if (byBarcode || p.sku.toUpperCase()===U)
      return { code, type:'product', id:p.id, entity:p,
        label:`${p.name} (${p.sku})`, sub:dbName('clients',p.client),
        extra:{ level: lvl||null, byBarcode } };
  }

  // 4) Outbound order — id OR client PO reference
  const ord = DB.outbound.find(o => o.id.toUpperCase()===U || String(o.ref||'').toUpperCase()===U);
  if (ord) return { code, type:'order', id:ord.id, entity:ord,
    label:ord.id, sub:`${ord.ref||''} · ${ord.status}`, extra:{} };

  // 5) ASN (inbound advance ship notice) — id
  const asn = DB.asns.find(a => a.id.toUpperCase()===U);
  if (asn) return { code, type:'asn', id:asn.id, entity:asn,
    label:asn.id, sub:`${dbName('clients',asn.client)} · ${asnStatus(asn)}`, extra:{} };

  return null;
}

/* ============================================================
   PHOTO / ATTACHMENT JUSTIFICATION (shared shape)
   Single flat collection — every photo references its owning entity OR a
   specific line by `ref` (a screen-chosen id string). One shape reused by
   Goods Reception, Stock-Out and Inventory-Ops; rendered + edited by the
   shared widget in assets/photos.js. Photos are OPTIONAL evidence, never
   mandatory. Mock = data-URL / filename placeholders (no real upload);
   every add/remove also writes a logTxn() audit row (the locked invariant).
     ref   : owning id — a document id (header) or a line/LPN ref (line)
     level : 'header' (whole document/event) | 'line' (one SKU/lot/LPN row)
   Line refs use a screen-local convention, e.g. `${docId}:L${idx}` or an LPN id.
   ============================================================ */
DB.attachments = DB.attachments || [];
let _attSeq = 700;
function nextAttId(){ return 'ATT-'+(++_attSeq); }
// Inline SVG placeholder so seeded/mock photos render without a real file.
function mockPhotoUrl(label, color){
  const c = color || '#2563eb', t = String(label==null?'PHOTO':label);
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='160' height='120'>`
    + `<rect width='160' height='120' fill='#eef2f7'/>`
    + `<rect x='1.5' y='1.5' width='157' height='117' fill='none' stroke='${c}' stroke-width='2'/>`
    + `<rect x='58' y='40' width='44' height='30' rx='4' fill='none' stroke='${c}' stroke-width='3'/>`
    + `<rect x='70' y='34' width='20' height='8' rx='2' fill='${c}'/>`
    + `<circle cx='80' cy='55' r='9' fill='none' stroke='${c}' stroke-width='3'/>`
    + `<circle cx='80' cy='55' r='3.5' fill='${c}'/>`
    + `<text x='80' y='100' text-anchor='middle' font-family='sans-serif' font-size='12' fill='#556'>${t}</text></svg>`;
  return 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);
}
function attachmentsFor(ref){ return DB.attachments.filter(a => a.ref === String(ref)); }
function attachmentCount(ref){ return attachmentsFor(ref).length; }
function addAttachment(o){
  o = o || {};
  const row = { id:nextAttId(), kind:'photo', ref:String(o.ref==null?'':o.ref), level:o.level||'header',
    name:o.name || 'photo.jpg', dataUrl:o.dataUrl || mockPhotoUrl('PHOTO'),
    caption:o.caption || '', by:o.by || 'AB', at:nowStamp() };
  DB.attachments.push(row);
  logTxn({ type:'attach', ref:row.ref, qty:0, user:row.by,
    note:`Photo attached (${row.level}): ${row.name}` });
  return row;
}
function removeAttachment(id){
  const i = DB.attachments.findIndex(a => a.id === id);
  if (i < 0) return false;
  const a = DB.attachments[i]; DB.attachments.splice(i,1);
  logTxn({ type:'attach-remove', ref:a.ref, qty:0, user:'AB', note:`Photo removed: ${a.name}` });
  return true;
}
// ---- Seed a few example photos so galleries aren't all empty on first load ----
(function seedAttachments(){
  const seed = (ref,level,name,label,color,caption) => DB.attachments.push({
    id:nextAttId(), kind:'photo', ref, level, name,
    dataUrl:mockPhotoUrl(label,color), caption:caption||'', by:'AB', at:'2026-06-16 09:12' });
  // Inbound: a damaged carton flagged at receipt (header + the affected line)
  seed('ASN-3001','header','delivery-truck.jpg','DELIVERY','#2563eb','Truck + packing slip on arrival');
  seed('ASN-3001:L0','line','carton-damage.jpg','DAMAGE','#dc2626','Crushed corner, lot L231201');
  // Outbound: proof-of-load on a dispatched order
  seed('OUT-7000','header','loaded-pallet.jpg','LOADED','#16a34a','Sealed pallet before loading');
  // Inventory: condition evidence on a customer return
  seed('RET-9001:L0','line','return-condition.jpg','RETURN','#d97706','Returned unit condition');
}());

/* ============================================================
   NOTES / REMARKS (shared shape — the textual sibling of attachments)
   A single free-text remark per entity OR per line, keyed by `ref` (the
   SAME ref scheme the photo widget uses, so a note and its photos sit
   side-by-side). One note per ref (setNote upserts; empty text clears it).
     ref   : owning id — a document/entity id (header) or a line/LPN ref (line)
     level : 'header' (whole document/event) | 'line' (one SKU/lot/LPN/loc row)
   Line refs follow the screen-local convention, e.g. `${docId}:L${idx}` or an
   LPN/location id (matching photos). Rendered + edited by the shared widget in
   assets/notes.js; read by reports via noteFor(ref). Notes are OPTIONAL and are
   lightweight remarks — unlike photo evidence they are NOT audited per-keystroke
   (no logTxn), so typing into a header/line note never spams the txn log.
   ============================================================ */
DB.notes = DB.notes || [];
let _noteSeq = 800;
function nextNoteId(){ return 'NOTE-'+(++_noteSeq); }
function noteRecFor(ref){ return DB.notes.find(n => n.ref === String(ref)) || null; }
function noteFor(ref){ const n = noteRecFor(ref); return n ? n.text : ''; }
function hasNote(ref){ return !!noteFor(ref); }
// Upsert the remark for a ref (one note per ref). Empty/blank text removes it.
function setNote(ref, text, opts){
  ref = String(ref==null?'':ref); const t = String(text==null?'':text); const o = opts || {};
  let rec = noteRecFor(ref);
  if (!t.trim()){ if (rec) DB.notes.splice(DB.notes.indexOf(rec),1); return null; }
  if (rec){ rec.text = t; rec.by = o.by||rec.by; rec.at = nowStamp(); }
  else { rec = { id:nextNoteId(), ref, level:o.level||'header', text:t, by:o.by||'AB', at:nowStamp() }; DB.notes.push(rec); }
  return rec;
}
// ---- Seed a few example remarks so headers/lines + report Notes columns aren't all empty ----
(function seedNotes(){
  const seed = (ref,level,text) => DB.notes.push({ id:nextNoteId(), ref, level, text, by:'AB', at:'2026-06-16 09:12' });
  seed('ASN-3001','header','Driver reported a damaged carton on pallet 2 — flagged for inspection on arrival.');
  seed('ASN-3001:L0','line','Crushed corner on lot L231201 — kept aside, photographed.');
  seed('OUT-7000','header','Customer requested delivery before noon; carrier briefed.');
  seed('OUT-7001','header','Fragile — bubble-wrap each bottle before pick.');
  seed('LPN-00012','header','Pallet wrap re-applied at inbound staging.');
  seed('RET-9001:L0','line','Returned unit unopened, original seal intact.');
}());

/* ============================================================
   PWA SESSION PERSISTENCE (opt-in; PWA flows only)
   The PWA scan-flows MUTATE the live DB and must carry those mutations
   ACROSS page navigations — a receive mints an LPN that then shows up in
   Putaway, becomes stock, gets picked. pwaHydrate() (called once by
   pwa-shell.js, before any screen reads DB) restores a sessionStorage
   snapshot over the seeded DB; pwaSaveDB() re-snapshots after each commit;
   pwaResetDB() clears it (back to seeds). ERP pages never call these, so the
   ERP keeps its in-memory reset-on-load mocks untouched. sessionStorage =
   survives navigation + refresh within the tab, clears on tab close or via
   the home "Reset demo data" control.
   ============================================================ */
const PWA_DB_KEY = 'wms.pwa.db';
// Only the mutable collections are snapshotted; the static masters stay from seed.
const PWA_DB_COLLECTIONS = ['lpns','pallets','asns','outbound','txns','moves','transfers','counts','physicals','repacks','returns','adjustments','attachments','notes','disposals','rtvs','grns','refusals'];
function pwaSaveDB(){
  try {
    const snap = {}; PWA_DB_COLLECTIONS.forEach(k => { snap[k] = DB[k]; });
    sessionStorage.setItem(PWA_DB_KEY, JSON.stringify(snap));
    return true;
  } catch(_){ return false; }
}
function pwaHydrate(){
  try {
    const raw = sessionStorage.getItem(PWA_DB_KEY); if (!raw) return false;
    const snap = JSON.parse(raw);
    PWA_DB_COLLECTIONS.forEach(k => { if (snap[k]) DB[k] = snap[k]; });
    // keep id counters ahead of hydrated data so freshly minted ids never collide
    (DB.txns || []).forEach(t => { const m = /TXN-(\d+)/.exec(t.id); if (m) _txnSeq = Math.max(_txnSeq, +m[1]); });
    (DB.attachments || []).forEach(a => { const m = /ATT-(\d+)/.exec(a.id); if (m) _attSeq = Math.max(_attSeq, +m[1]); });
    return true;
  } catch(_){ return false; }
}
function pwaResetDB(){ try { sessionStorage.removeItem(PWA_DB_KEY); } catch(_){} }

/* ---- Receipt routing: staging (wait/put) + quarantine locations for a site ---- */
function stagingLocFor(site){ const l = DB.locations.find(x => x.site===site && x.type==='wait/put'   && x.status!=='inactive'); return l ? l.id : ''; }
function quarantineLocFor(site){ const l = DB.locations.find(x => x.site===site && x.type==='quarantine' && x.status!=='inactive'); return l ? l.id : ''; }

/* ============================================================
   MIXED (AGGREGATE) RECEIVING PALLET — transient handling unit. DB.pallets[].
   One pallet holds MANY product/lot lines under ONE license plate + one label
   (the real 3PL "mixed pallet"). It is TRANSIENT: it carries goods across the
   receive → putaway leg as a single scan, then DECOMPOSES — each line, as it is
   put away, mints a normal homogeneous DB.lpns plate (the persistent child stock).
   When the last line is placed the pallet is 'closed'. Persistent stock therefore
   stays one-product-per-LPN, so every stock / pick / report helper is untouched.
     id     : 'PLT-#####'  (an SSCC-style plate in production)
     lines[]: { product, qty, lot, expiry, serials[] }   (one received line each)
     status : 'to-putaway' (open, awaiting decomposition) | 'closed' (fully placed)
   ============================================================ */
DB.pallets = DB.pallets || [];
function nextPalletId(){ let n=0; (DB.pallets||[]).forEach(p=>{ const m=/PLT-(\d+)/.exec(p.id); if(m) n=Math.max(n,+m[1]); }); return 'PLT-'+String(n+1).padStart(5,'0'); }
function palletById(id){ return (DB.pallets||[]).find(p=>p.id===id) || null; }
function palletOpenLines(p){ return ((p&&p.lines)||[]).filter(l=>(l.qty||0)>0); }
function palletTotals(p){ const ls=palletOpenLines(p); return { lines:ls.length, units:ls.reduce((s,l)=>s+(l.qty||0),0) }; }
function palletsAtSite(site, client){ return (DB.pallets||[]).filter(p=>p.status==='to-putaway' && p.site===site && (!client||p.client===client) && palletOpenLines(p).length); }
// Decompose ONE pallet line into a persistent child LPN at a bin (the putaway step).
// Mints a homogeneous DB.lpns plate carrying the line's genealogy, decrements the line, closes the
// pallet when no open lines remain, and writes a putaway txn. Returns the new LPN id (or null).
// `opts.qty` (optional) places only that many — a PARTIAL line placement (split across bins): the
// remainder stays open on the line for the next bin. Omit `opts.qty` to place the WHOLE line (default).
function decomposePalletLine(palletId, lineIdx, binId, opts){
  const p = palletById(palletId); if (!p || p.status!=='to-putaway') return null;
  const ln = (p.lines||[])[lineIdx]; if (!ln || !(ln.qty>0)) return null;
  const o = opts||{};
  const q = (o.qty!=null) ? Math.min(Math.floor(Number(o.qty)||0), ln.qty) : ln.qty;
  if (!(q>0)) return null;
  const id = nextLpnId();
  const ser = Array.isArray(ln.serials) ? ln.serials : [];
  DB.lpns.push({ id, client:p.client, site:p.site, product:ln.product, qty:q,
    lot:ln.lot||'', expiry:ln.expiry||'', serials:ser.slice(0,q), status:'available', loc:binId });
  logTxn({ type:'putaway', lpn:id, product:ln.product, qty:q, from:p.loc||'', to:binId,
    site:p.site, user:o.user||'', ref:p.id, note:o.note||`decompose ${p.id}` });
  ln.qty -= q; ln.serials = ser.slice(q);            // remainder (if any) stays open for the next bin
  if (!palletOpenLines(p).length) p.status = 'closed';
  return id;
}
// Place `qty` of a to-putaway LPN into bin `binId` (the single-LPN putaway step). Whole-plate placement
// stores the plate itself (status→available, no new id); a PARTIAL mints a child LPN of `qty` at the bin
// and decrements the source (remainder stays to-putaway → reappears as a task) — split across bins.
// Conserves quantity + carries lot/expiry/serial genealogy. Returns { placedId, remainder, split } or null.
// The CALLER validates the bin (capacity / segregation / frozen) BEFORE calling, per the screen flow.
function putawayPlace(lpnId, binId, qty, opts){
  const l = lpnById(lpnId); if (!l || l.status!=='to-putaway') return null;
  const q = Math.min(Math.floor(Number(qty)||0), l.qty); if (!(q>0)) return null;
  const from = l.loc, o = opts||{};
  if (q === l.qty){                                  // whole remainder → store the plate itself (keeps its id)
    l.status = 'available'; l.loc = binId;
    logTxn({ type:'putaway', lpn:l.id, product:l.product, qty:q, from, to:binId, site:l.site,
      user:o.user||'', ref:o.ref||'putaway', note:o.note||`Putaway → ${locName(binId)}` });
    return { placedId:l.id, remainder:0, split:false };
  }
  const id = nextLpnId();                             // partial → mint child of q at the bin
  const ser = Array.isArray(l.serials) ? l.serials : [];
  DB.lpns.push({ id, client:l.client, site:l.site, product:l.product, qty:q,
    lot:l.lot||'', expiry:l.expiry||'', serials:ser.slice(0,q), status:'available', loc:binId });
  l.qty -= q; l.serials = ser.slice(q);              // source remainder stays to-putaway
  logTxn({ type:'putaway', lpn:id, product:l.product, qty:q, from, to:binId, site:l.site,
    user:o.user||'', ref:o.ref||l.id, note:o.note||`Putaway split from ${l.id} → ${locName(binId)}` });
  return { placedId:id, remainder:l.qty, split:true };
}
// ---- Inspection decision (accept / reject, with PARTIAL split) ----
// A to-inspect plate of qty Q splits into an ACCEPTED portion (→ to-putaway: enters the putaway queue, becomes
// available stock once stored) and a REJECTED portion (→ a blocked disposition: quarantine | hold | damaged —
// excluded from availability, so it never enters sellable stock). Whole-accept / whole-reject keep the plate's id;
// a PARTIAL keeps the accepted qty on the original plate and mints a child LPN for the rejected qty. Conserves
// quantity (accepted + rejected = original) and carries lot/expiry/serial genealogy. Writes 'inspect' txns.
// Returns { acceptedId, rejectedId, accepted, rejected } or null. opts: { disposition, reason, user, ref, note }.
function inspectionSplit(lpnId, acceptQty, opts){
  const l = lpnById(lpnId); if (!l || l.status!=='to-inspect') return null;
  const Q = l.qty||0;
  const A = Math.max(0, Math.min(Math.floor(Number(acceptQty)||0), Q)), R = Q - A;
  const o = opts||{}, disp = o.disposition||'quarantine', reason = o.reason||'';
  const ser = Array.isArray(l.serials) ? l.serials : null;
  const dispLoc = (disp==='quarantine'||disp==='damaged') ? (quarantineLocFor(l.site)||l.loc) : l.loc;
  const res = { acceptedId:null, rejectedId:null, accepted:A, rejected:R };
  const fromLoc = l.loc;

  if (R === 0){                          // accept all → the plate continues to putaway (keeps its id)
    l.status = 'to-putaway';
    logTxn({ type:'inspect', lpn:l.id, product:l.product, qty:A, from:fromLoc, to:l.loc, site:l.site, user:o.user||'', ref:o.ref||'inspection', note:o.note||'Inspection: accepted (all) → to-putaway' });
    res.acceptedId = l.id; return res;
  }
  if (A === 0){                          // reject all → the plate goes to the disposition (keeps its id)
    l.status = disp; l.loc = dispLoc;
    logTxn({ type:'inspect', lpn:l.id, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||'', ref:o.ref||'inspection', note:o.note||`Inspection: rejected (all) → ${disp}${reason?' · '+reason:''}` });
    res.rejectedId = l.id; return res;
  }
  // PARTIAL: accepted qty stays on the original plate (→ to-putaway); rejected qty becomes a child at the disposition.
  l.qty = A; if (ser) l.serials = ser.slice(0, A); l.status = 'to-putaway';
  logTxn({ type:'inspect', lpn:l.id, product:l.product, qty:A, from:fromLoc, to:l.loc, site:l.site, user:o.user||'', ref:o.ref||'inspection', note:o.note||'Inspection: accepted (partial) → to-putaway' });
  const rid = nextLpnId();
  DB.lpns.push({ id:rid, client:l.client, site:l.site, product:l.product, qty:R,
    lot:l.lot||'', expiry:l.expiry||'', serials: ser ? ser.slice(A) : [], status:disp, loc:dispLoc });
  logTxn({ type:'inspect', lpn:rid, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||'', ref:o.ref||l.id, note:o.note||`Inspection: rejected (partial) → ${disp}${reason?' · '+reason:''}` });
  res.acceptedId = l.id; res.rejectedId = rid; return res;
}

// ---- Putaway-stage damage / reject (partial split) ----
// Damage discovered AT PUTAWAY — after the inspection gate, or on good stock that skipped inspection (the operator
// is about to slot the plate and finds some units crushed). Peel the REJECT units off a to-putaway plate to a blocked
// disposition (quarantine | hold | damaged — excluded from availability), leaving the GOOD remainder to-putaway so it
// keeps flowing into a bin. Whole-reject flips the plate's own status (keeps its id); a PARTIAL keeps the good qty on
// the original plate (still to-putaway) and mints a child LPN for the rejected qty at the disposition location.
// Conserves quantity (good + rejected = original) and carries lot/expiry/serial genealogy. Logs a 'status' txn (the
// same stock-status-change type Inventory uses) so the reject lands in the audit trail / txn report — NOT a 'putaway'
// txn, so it never shows as a completed putaway. Returns { goodId, rejectedId, good, rejected } or null.
// opts: { disposition, reason, user, ref, note }.
function putawayReject(lpnId, rejectQty, opts){
  const l = lpnById(lpnId); if (!l || l.status!=='to-putaway') return null;
  const Q = l.qty||0;
  const R = Math.max(0, Math.min(Math.floor(Number(rejectQty)||0), Q)), G = Q - R;
  if (!(R>0)) return null;                 // nothing rejected → use putawayPlace instead
  const o = opts||{}, disp = o.disposition||'damaged', reason = o.reason||'';
  const ser = Array.isArray(l.serials) ? l.serials : null;
  const dispLoc = (disp==='quarantine'||disp==='damaged') ? (quarantineLocFor(l.site)||l.loc) : l.loc;
  const note = o.note || `to-putaway → ${disp}${reason?' · '+reason:''} (putaway reject)`;
  const res = { goodId:null, rejectedId:null, good:G, rejected:R };
  const fromLoc = l.loc;

  if (G === 0){                            // reject all → the plate itself goes to the disposition (keeps its id)
    l.status = disp; l.loc = dispLoc;
    logTxn({ type:'status', lpn:l.id, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||'', ref:o.ref||l.id, note });
    res.rejectedId = l.id; return res;
  }
  // PARTIAL: good qty stays on the original plate (still to-putaway); rejected qty becomes a child at the disposition.
  l.qty = G; if (ser) l.serials = ser.slice(0, G);
  const rid = nextLpnId();
  DB.lpns.push({ id:rid, client:l.client, site:l.site, product:l.product, qty:R,
    lot:l.lot||'', expiry:l.expiry||'', serials: ser ? ser.slice(G) : [], status:disp, loc:dispLoc });
  logTxn({ type:'status', lpn:rid, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||'', ref:o.ref||l.id, note });
  res.goodId = l.id; res.rejectedId = rid; return res;
}

// Seed one demo mixed pallet at Luanda staging (ACME) so Putaway can be demoed even before building one in Receive.
if (!DB.pallets.length) DB.pallets.push({
  id:'PLT-00001', client:'C-ACME', site:'S-LYON', status:'to-putaway', loc:'LOC-WAIT-01',
  lines:[
    { product:'P-1001', qty:24, lot:'L-OLV-PLT', expiry:'2027-03-31', serials:[] },
    { product:'P-TCA',  qty:10, lot:'',          expiry:'',           serials:[] },
    { product:'P-TCB',  qty:15, lot:'L-TCB-PLT', expiry:'',           serials:[] }
  ]
});

// All putaway placements recorded against a source handling unit — either a still-open source LPN id (its
// partial-putaway children) or a pallet id (its decomposition children). The "what's already been put away
// from this plate/pallet" history; insertion order (oldest first). Drives the read-only partial-progress UX.
function putawaysFromSource(sourceId){ return (DB.txns||[]).filter(t => t.type==='putaway' && t.ref===sourceId); }
// Partial-putaway progress for a still-open (to-putaway) source LPN: how much is already placed (and where)
// vs how much remains on the plate. Returns null for an untouched plate (nothing placed yet).
function lpnPutawayProgress(lpnId){
  const l = lpnById(lpnId); if (!l) return null;
  const placements = putawaysFromSource(lpnId);
  if (!placements.length) return null;
  const placed = placements.reduce((s,t)=>s+(t.qty||0),0);
  const remaining = l.qty||0;
  return { placed, remaining, original: placed+remaining, placements };
}

// Seed two IN-PROGRESS demos (ACME / Luanda) so the partial-progress UX shows on load:
//   (1) a single plate part-put-away: LPN-00120 (20 left) + already-placed child LPN-00121 (80 @ a bin);
//   (2) a part-decomposed pallet PLT-00003: one line already placed (child LPN-00122), two lines still open.
if (!lpnById('LPN-00120')){
  DB.lpns.push(
    { id:'LPN-00120', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:20, lot:'L231201', expiry:'2026-06-30', serials:[], status:'to-putaway', loc:'LOC-WAIT-01' },
    { id:'LPN-00121', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:80, lot:'L231201', expiry:'2026-06-30', serials:[], status:'available',  loc:'LOC-TC01' },
    { id:'LPN-00122', client:'C-ACME', site:'S-LYON', product:'P-TCA',  qty:10, lot:'',        expiry:'',           serials:[], status:'available',  loc:'LOC-TC02' }
  );
  DB.txns.push(
    { id:'TXN-1004', ts:'2026-06-18 08:15', type:'putaway', lpn:'LPN-00121', product:'P-1001', qty:80, from:'LOC-WAIT-01', to:'LOC-TC01', site:'S-LYON', user:'Benjamin Felix — Supervisor', ref:'LPN-00120', note:'Putaway (partial) — 80 of 100' },
    { id:'TXN-1005', ts:'2026-06-18 08:40', type:'putaway', lpn:'LPN-00122', product:'P-TCA',  qty:10, from:'LOC-WAIT-01', to:'LOC-TC02', site:'S-LYON', user:'Benjamin Felix — Supervisor', ref:'PLT-00003', note:'Decompose PLT-00003 (partial)' }
  );
}
if (!palletById('PLT-00003')) DB.pallets.push({
  id:'PLT-00003', client:'C-ACME', site:'S-LYON', status:'to-putaway', loc:'LOC-WAIT-01', asn:'',
  lines:[
    { product:'P-TCA',  qty:0,  lot:'',           expiry:'',           serials:[] },   // already placed → child LPN-00122 (see TXN-1005)
    { product:'P-1001', qty:18, lot:'L-OLV-PLT2', expiry:'2027-06-30', serials:[] },
    { product:'P-TCB',  qty:10, lot:'L-TCB-PLT2', expiry:'',           serials:[] }
  ]
});

/* ============================================================
   EDGE-CASE PROGRAM (2026-06-19) — shared helpers, new collections,
   statuses, reason domains + seed for closing the pre-coding audit
   gaps. See EDGE_CASE_TRACKER.md. Appended (not interleaved) to keep
   the diff legible; all of this runs after the DB literal is built.
   New LPN statuses: 'disposed' (scrapped/destroyed — terminal),
   'lost' (in-transit loss / shrinkage — terminal). New ASN.state:
   'cancelled' | 'refused'. New txn types: 'dispose','rtv','refuse',
   'transfer-cancel','transfer-loss','park'.
   ============================================================ */

/* ---- Mock current user + maker-checker (F13 separation of duties) ---- */
DB.currentUser = 'Benjamin Felix — Supervisor';
function setCurrentUser(name){ if (name) DB.currentUser = name; }
function currentUser(){ return DB.currentUser; }
// True when the would-be approver IS the raiser (so Approve must be blocked).
function sameActor(raisedBy){ return !!raisedBy && String(raisedBy) === String(DB.currentUser); }

/* ---- Work-item ASSIGNMENT ("dispatch a request to a person" + the "My requests" filter) ----
   An optional `assignee` (→ User.id) on a work item. Absent / '' = UNASSIGNED (shows as "Any").
   ERP supervisors dispatch work; both the ERP grids and the PWA task lists can filter to "mine".
   `DB.currentUserId` is the mock logged-in user; the PWA shell re-points it at the floor operator
   on load (PWA.userId), so isMine() resolves to the right person in BOTH channels with no per-screen
   plumbing. [mock] in production the assignee + current user are real User ids from the session.
   NOTE (coding phase): PWA self-claim must be ROLE-GATED — same posture as Express Fulfil / ad-hoc
   dispatch (shown to all in the mock). */
DB.currentUserId = DB.currentUserId || 'U-002';   // Benjamin Felix — Supervisor (matches DB.currentUser)
function assigneeName(id){ return id ? dbName('users', id) : 'Any'; }
function isMine(rec){ return !!(rec && rec.assignee && rec.assignee === DB.currentUserId); }
function isAssignedTo(rec, userId){ return !!(rec && rec.assignee && rec.assignee === userId); }
// Active users who can take floor work at a site = the assignee dropdown options. Site scope is a
// display string in the mock ('All sites' | a site name); match "all" or the exact site name, and
// fall back to every active user if the scope filter would be empty.
function assignableUsers(siteId){
  const sName = (DB.sites.find(s=>s.id===siteId)||{}).name || '';
  const scoped = DB.users.filter(u => u.status==='active' && (/all/i.test(u.sites||'') || u.sites===sName));
  return (siteId && scoped.length) ? scoped : DB.users.filter(u=>u.status==='active');
}
// Build the standard <option> list for an Assignee FILTER select: Any · ★ My requests · each user.
function assigneeFilterOptions(siteId, selected){
  const opt = (v,l)=>`<option value="${v}" ${v===selected?'selected':''}>${l}</option>`;
  return opt('all','Any')
    + opt('mine', '★ My requests — '+assigneeName(DB.currentUserId))
    + assignableUsers(siteId).map(u=>opt(u.id, u.name + (u.id===DB.currentUserId?' (me)':''))).join('');
}
// Build the standard <option> list for an Assignee PICKER (dispatch): Any (unassigned) + each user.
function assigneePickerOptions(siteId, selected){
  const opt = (v,l)=>`<option value="${v}" ${v===(selected||'')?'selected':''}>${l}</option>`;
  return opt('','— Any —') + assignableUsers(siteId).map(u=>opt(u.id, u.name)).join('');
}
// Apply the Assignee filter state ('all' | 'mine' | a User.id) to a work-item record.
function assigneeFilterPass(rec, fstate){
  if (!fstate || fstate==='all') return true;
  if (fstate==='mine') return isMine(rec);
  return rec && rec.assignee === fstate;
}

/* ---- Reservations against a plate (F3 orphan-allocation guard; shared) ---- */
// Open orders whose allocation reserves this LPN — decreasing / moving / shipping / disposing it would
// orphan these reservations. Returns [{ order, qty }].
function ordersReserving(lpnId){
  const out = [];
  (DB.outbound||[]).forEach(o => {
    if (!['allocated','picking','picked','partial'].includes(o.status)) return;
    let q = 0; (o.lines||[]).forEach(ln => (ln.alloc||[]).forEach(a => { if (a.lpn===lpnId) q += (a.qty||0); }));
    if (q>0) out.push({ order:o.id, qty:q });
  });
  return out;
}

/* ---- Dispatch re-validation at COMMIT (C1) ---- */
// Re-assert every allocated plate is still issuable: present, not blocked/terminal, not past-expiry, not in a
// frozen take. Returns { ok, fails:[{lpn, why}] }. Call inside confirm handlers BEFORE issuing stock.
function dispatchGuard(allocLines){
  const fails = [];
  (allocLines||[]).forEach(a => {
    const id = a.lpn; if (!id) return;
    const l = lpnById(id);
    if (!l)                                                            fails.push({ lpn:id, why:'plate no longer exists' });
    else if (['dispatched','consumed','disposed','lost'].includes(l.status)) fails.push({ lpn:id, why:`already ${l.status}` });
    else if (isBlocked(l.status))                                      fails.push({ lpn:id, why:`blocked (${l.status})` });
    else if (isExpired(l))                                             fails.push({ lpn:id, why:'past expiry' });
    else if (isLocFrozen(l.loc))                                       fails.push({ lpn:id, why:`frozen — ${(frozenTakeFor(l.loc)||{}).id||'stock-take'}` });
    else if ((l.qty||0) < (a.picked||a.qty||0))                        fails.push({ lpn:id, why:`only ${l.qty} on plate` });
  });
  return { ok: fails.length===0, fails };
}

/* ---- Serial validation on issue (F15) ---- */
// Expand a serials string into explicit units. Understands explicit lists (comma/space/newline) AND a seeded
// range token like 'SN-301…360' / 'SN-TCD-101…150' (prefix + start…end), so demo stock that carries ranges still
// validates to its qty. (The [mock] note: production stores explicit lists.)
function expandSerials(raw){
  const out = [];
  String(raw||'').split(/[\s,;]+/).map(s=>s.trim()).filter(Boolean).forEach(tok => {
    const m = /^(.*?)(\d+)\s*(?:…|\.\.|–|—)\s*(\d+)$/.exec(tok);
    if (m){ const pre=m[1], a=+m[2], b=+m[3], w=m[2].length;
      if (b>=a && (b-a)<100000){ for(let n=a;n<=b;n++) out.push(pre+String(n).padStart(w,'0')); return; } }
    out.push(tok);
  });
  return out;
}
// Must be non-empty, count === picked qty, and no duplicates. Returns { ok, serials, error }.
function validateSerials(raw, qty){
  const serials = expandSerials(raw);
  const need = Math.max(0, Math.floor(Number(qty)||0));
  if (!serials.length)            return { ok:false, serials, error:'No serials captured' };
  if (serials.length !== need)    return { ok:false, serials, error:`Serial count ${serials.length} ≠ picked qty ${need}` };
  const dup = serials.find((s,i)=>serials.indexOf(s)!==i);
  if (dup)                        return { ok:false, serials, error:`Duplicate serial "${dup}"` };
  return { ok:true, serials, error:'' };
}

/* ---- Damage found AT PICK (F8) ---- */
// Peel REJECT units off a pickable plate to a blocked disposition (mirror of putawayReject for the outbound side).
// Whole-reject flips the plate's own status; a partial keeps the good qty and mints a child at the disposition loc.
// Logs a 'status' txn (audit), NOT a dispatch. opts: { disposition, reason, user, ref, note }.
function pickReject(lpnId, rejectQty, opts){
  const l = lpnById(lpnId); if (!l) return null;
  const Q = l.qty||0, R = Math.max(0, Math.min(Math.floor(Number(rejectQty)||0), Q)), G = Q - R;
  if (!(R>0)) return null;
  const o = opts||{}, disp = o.disposition||'damaged', reason = o.reason||'';
  const ser = Array.isArray(l.serials) ? l.serials : null;
  const dispLoc = (disp==='quarantine'||disp==='damaged') ? (quarantineLocFor(l.site)||l.loc) : l.loc;
  const note = o.note || `${l.status} → ${disp}${reason?' · '+reason:''} (damage found at pick)`;
  const fromLoc = l.loc, res = { goodId:null, rejectedId:null, good:G, rejected:R };
  if (G === 0){ l.status = disp; l.loc = dispLoc;
    logTxn({ type:'status', lpn:l.id, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||DB.currentUser, ref:o.ref||l.id, note });
    res.rejectedId = l.id; return res; }
  l.qty = G; if (ser) l.serials = ser.slice(0, G);
  const rid = nextLpnId();
  DB.lpns.push({ id:rid, client:l.client, site:l.site, product:l.product, qty:R, lot:l.lot||'', expiry:l.expiry||'', serials: ser?ser.slice(G):[], status:disp, loc:dispLoc });
  logTxn({ type:'status', lpn:rid, product:l.product, qty:R, from:fromLoc, to:dispLoc, site:l.site, user:o.user||DB.currentUser, ref:o.ref||l.id, note });
  res.goodId = l.id; res.rejectedId = rid; return res;
}
// Auto-raise a single-line pending-approval count when stock is reported NOT FOUND at a bin (F8). Feeds erp-inv-count.
function flagCountForMissing(o){
  const id = (function(){ let n=0; (DB.counts||[]).forEach(c=>{const m=/CNT-(\d+)/.exec(c.id); if(m)n=Math.max(n,+m[1]);}); return 'CNT-'+String(n+1).padStart(4,'0'); })();
  const l = lpnById(o.lpn);
  const sheet = { id, site:o.site||(l&&l.site)||'', status:'pending-approval', created:nowStamp(),
    countedBy:o.by||DB.currentUser, countedDate:nowStamp(), source:'pick-not-found',
    locations:[{ loc:o.loc||(l&&l.loc)||'', lines:[{ lpn:o.lpn||'', product:o.product||(l&&l.product)||'', lot:(l&&l.lot)||'', systemQty:(l&&l.qty)||o.qty||0, countedQty:0 }] }] };
  (DB.counts = DB.counts||[]).push(sheet);
  logTxn({ type:'count', lpn:o.lpn||'', product:o.product||'', qty:0, site:sheet.site, user:sheet.countedBy, ref:id, note:`Stock not found at pick → count raised (${o.loc||''})` });
  return sheet;
}

/* ---- Mixed-pallet LINE damage reject (F12) ---- */
// Peel REJECT units off a pallet manifest line to a blocked disposition; decrement the line; close the pallet when
// every line is empty. Mints a child LPN at the disposition loc (genealogy carried). Returns { rejectedId, ... }.
function palletLineReject(palletId, lineIdx, rejectQty, opts){
  const p = palletById(palletId); if (!p) return null;
  const line = (p.lines||[])[lineIdx]; if (!line) return null;
  const Q = line.qty||0, R = Math.max(0, Math.min(Math.floor(Number(rejectQty)||0), Q));
  if (!(R>0)) return null;
  const o = opts||{}, disp = o.disposition||'damaged', reason = o.reason||'';
  const ser = Array.isArray(line.serials) ? line.serials : null;
  const dispLoc = (disp==='quarantine'||disp==='damaged') ? (quarantineLocFor(p.site)||p.loc) : p.loc;
  const rid = nextLpnId();
  DB.lpns.push({ id:rid, client:p.client, site:p.site, product:line.product, qty:R, lot:line.lot||'', expiry:line.expiry||'', serials: ser?ser.slice(0,R):[], status:disp, loc:dispLoc });
  line.qty = Q - R; if (ser) line.serials = ser.slice(R);
  logTxn({ type:'status', lpn:rid, product:line.product, qty:R, from:p.loc, to:dispLoc, site:p.site, user:o.user||DB.currentUser, ref:o.ref||palletId, note:o.note||`pallet ${palletId} line → ${disp}${reason?' · '+reason:''} (putaway reject)` });
  if (!palletOpenLines(p).length) p.status = 'closed';
  return { rejectedId:rid, rejected:R, remaining:line.qty };
}

/* ---- Putaway overflow / park (F10) ---- */
// A designated overflow staging bin for "nothing fits" — distinct from the inbound staging bin, so a parked plate
// reads as deliberately parked (not silently stuck). Falls back to staging if no overflow bin exists.
function overflowLocFor(site){
  const ovf = DB.locations.find(x => x.site===site && x.type==='wait/put' && /overflow/i.test(x.userRef||'') && x.status!=='inactive');
  return ovf ? ovf.id : stagingLocFor(site);
}
// Park a to-putaway plate to the overflow bin (keeps it to-putaway; logs a 'park' txn so it's visible/resumable).
function parkToOverflow(lpnId, opts){
  const l = lpnById(lpnId); if (!l || l.status!=='to-putaway') return null;
  const dest = overflowLocFor(l.site); if (!dest || dest===l.loc) return null;
  const from = l.loc, o = opts||{}; l.loc = dest;
  logTxn({ type:'park', lpn:l.id, product:l.product, qty:l.qty, from, to:dest, site:l.site, user:o.user||DB.currentUser, ref:o.ref||l.id, note:o.note||'Parked to overflow — no bin available' });
  return dest;
}

/* ---- Expiry transition + cleanup (F11) ---- */
// Flip a single past-expiry available plate to the 'expired' (blocked) status. Reason-coded, logs a 'status' txn.
function flipExpired(lpnId, opts){
  const l = lpnById(lpnId); if (!l || l.status!=='available' || !isExpired(l)) return false;
  const o = opts||{}, from = l.status; l.status = 'expired';
  logTxn({ type:'status', lpn:l.id, product:l.product, qty:l.qty, from:l.loc, to:l.loc, site:l.site, user:o.user||DB.currentUser, ref:o.ref||l.id, note:o.note||`${from} → expired · ${o.reason||'Shelf-life / expiry date passed'}` });
  return true;
}
// Sweep every past-expiry available plate at a site to 'expired'. Returns the count flipped.
function sweepExpired(site, opts){
  let n = 0;
  DB.lpns.filter(l => (!site||l.site===site) && l.status==='available' && isExpired(l)).forEach(l => { if (flipExpired(l.id, opts)) n++; });
  return n;
}

/* ---- Cold-chain carrier match (F20) ---- */
function coldChainProduct(id){
  const p = DB.products.find(x => x.id===id); if (!p) return false;
  return p.subCategory==='SUB-VAX' || /cold|vacc|chill|2.?8.?°?c/i.test(`${subCatName(p.subCategory)||''} ${catName(p.category)||''}`);
}
function carrierIsCold(id){ const c = (DB.carriers||[]).find(x => x.id===id); return !!(c && /°c|cold|chill|reefer|2.?8/i.test(c.mode||'')); }

/* ---- Disposal / scrap-out (F5) — approval-gated, terminal ---- */
DB.disposals = DB.disposals || [];
function nextDspId(){ let n=0; DB.disposals.forEach(d=>{const m=/DSP-(\d+)/.exec(d.id); if(m)n=Math.max(n,+m[1]);}); return 'DSP-'+String(n+1).padStart(4,'0'); }
function disposeCreate(o){
  const l = lpnById(o.lpn); if (!l) return null;
  const qty = Math.max(0, Math.min(Math.floor(Number(o.qty)||0), l.qty||0));
  const d = { id:nextDspId(), client:l.client, site:l.site, lpn:l.id, product:l.product, qty,
    method:o.method||'scrap', reason:o.reason||'', note:o.note||'', status:'pending',
    by:o.by||DB.currentUser, created:nowStamp(), approver:'', posted:'' };
  DB.disposals.push(d); return d;
}
function disposeApprove(id, user){
  const d = DB.disposals.find(x=>x.id===id); if (!d || d.status!=='pending') return null;
  const l = lpnById(d.lpn); if (!l) return null;
  const q = Math.min(d.qty, l.qty||0);
  l.qty = (l.qty||0) - q; if (l.qty<=0){ l.qty = 0; l.status = 'disposed'; }
  d.status = 'posted'; d.approver = user||DB.currentUser; d.posted = nowStamp();
  logTxn({ type:'dispose', lpn:l.id, product:l.product, qty:q, from:l.loc, to:l.loc, site:l.site, user:d.approver, ref:d.id, note:`Disposed (${d.method}) ${q} · ${d.reason}` });
  return d;
}
function disposeReject(id, user){ const d = DB.disposals.find(x=>x.id===id); if (!d || d.status!=='pending') return null; d.status='rejected'; d.approver=user||DB.currentUser; d.posted=nowStamp(); return d; }

/* ---- Return-to-vendor / return-to-client (F6) ---- */
DB.rtvs = DB.rtvs || [];
function nextRtvId(){ let n=0; DB.rtvs.forEach(r=>{const m=/RTV-(\d+)/.exec(r.id); if(m)n=Math.max(n,+m[1]);}); return 'RTV-'+String(n+1).padStart(4,'0'); }
function rtvDestName(rtv){ return rtv.destType==='supplier' ? dbName('suppliers', rtv.dest) : dbName('clients', rtv.dest); }
// Issue every line's qty out of stock back to the vendor/client. Decrement; flip to 'dispatched' when emptied.
function rtvIssue(rtv, user){
  (rtv.lines||[]).forEach(ln => {
    const l = lpnById(ln.lpn); if (!l) return;
    const q = Math.min(ln.qty||0, l.qty||0);
    l.qty = (l.qty||0) - q; if (l.qty<=0){ l.qty = 0; l.status = 'dispatched'; }
    logTxn({ type:'rtv', lpn:l.id, product:l.product, qty:q, from:l.loc, to:(rtv.destType==='supplier'?'(supplier)':'(client)'), site:rtv.site, user:user||DB.currentUser, ref:rtv.id, note:`RTV → ${rtv.destType} ${rtvDestName(rtv)} · ${rtv.reason||''}` });
  });
  rtv.status = 'shipped'; rtv.shipped = nowStamp(); rtv.by = user||DB.currentUser;
  return rtv;
}

/* ---- Delivery refusal + ASN void/cancel (F4) ---- */
DB.refusals = DB.refusals || [];
function nextRefusalId(){ let n=0; DB.refusals.forEach(r=>{const m=/REF-(\d+)/.exec(r.id); if(m)n=Math.max(n,+m[1]);}); return 'REF-'+String(n+1).padStart(4,'0'); }
// Record a reasoned refusal — NO STOCK MINTED (goods never enter). Optionally marks the linked ASN 'refused'.
function refuseDelivery(o){
  const r = { id:nextRefusalId(), client:o.client||'', site:o.site||'', asn:o.asn||'', supplier:o.supplier||'',
    carrier:o.carrier||'', reason:o.reason||'', note:o.note||'', by:o.by||DB.currentUser, created:nowStamp() };
  DB.refusals.push(r);
  if (o.asn){ const a = (DB.asns||[]).find(x=>x.id===o.asn); if (a) a.state = 'refused'; }
  logTxn({ type:'refuse', lpn:'', product:'', qty:0, from:'', to:'(refused — kept outside WH)', site:o.site||'', user:r.by, ref:o.asn||r.id, note:`Delivery refused${o.supplier?' · '+dbName('suppliers',o.supplier):''}${o.reason?' · '+o.reason:''}` });
  return r;
}
function cancelAsn(asnId, opts){
  const a = (DB.asns||[]).find(x=>x.id===asnId); if (!a) return null;
  a.state = 'cancelled'; const o = opts||{};
  logTxn({ type:'status', lpn:'', product:'', qty:0, site:a.site, user:o.by||DB.currentUser, ref:asnId, note:`ASN cancelled / voided${o.reason?' · '+o.reason:''}` });
  return a;
}

/* ---- GRN per receipt + duplicate-receipt guard (F24 / F16) ---- */
DB.grns = DB.grns || [];
function nextGrnId(){ let n=0; DB.grns.forEach(g=>{const m=/GRN-(\d+)/.exec(g.id); if(m)n=Math.max(n,+m[1]);}); return 'GRN-'+String(n+1).padStart(4,'0'); }
function grnCreate(o){
  const g = { id:nextGrnId(), client:o.client, site:o.site, asn:o.asn||'', supplier:o.supplier||'',
    deliveryRef:o.deliveryRef||'', date:nowStamp(), by:o.by||DB.currentUser,
    lines:(o.lines||[]).map(L=>({ product:L.product, qty:L.qty, lot:L.lot||'', expiry:L.expiry||'', condition:L.condition||'good', lpn:L.lpn||'' })) };
  DB.grns.push(g); return g;
}
// True if this supplier delivery-note ref was already received (idempotency / duplicate-delivery guard).
function receiptRefSeen(deliveryRef, client){
  if (!deliveryRef) return false;
  return (DB.grns||[]).some(g => g.deliveryRef && g.deliveryRef.toLowerCase()===String(deliveryRef).toLowerCase() && (!client||g.client===client));
}
// Open ASNs for a product at a client/site (F2b — blind receipt ↔ open ASN reconciliation).
function openAsnsForProduct(product, client, site){
  return (DB.asns||[]).filter(a => a.client===client && a.site===site && asnStatus(a)!=='closed' && a.state!=='cancelled' && a.state!=='refused'
    && (a.lines||[]).some(l => l.product===product && (l.received||0) < l.qty));
}

/* ---- Overflow + extra blocked seed (so the new screens render with demo data) ---- */
DB.locations.push(
  { id:'LOC-OVF-01',  site:'S-LYON',  type:'wait/put', path:{Zone:'OVF'}, structured:'OVF-01', userRef:'Overflow staging', status:'active' },
  { id:'LOC-P-OVF01', site:'S-PARIS', type:'wait/put', path:{Zone:'OVF'}, structured:'OVF-01', userRef:'Overflow staging', status:'active' }
);
// A damaged plate (ACME) at quarantine — feeds the Disposal + RTV demos without colliding with LPN-00005 (GLBX quarantine).
if (!lpnById('LPN-00040')) DB.lpns.push(
  { id:'LPN-00040', client:'C-ACME', site:'S-LYON', product:'P-1001', qty:40, lot:'L231201', expiry:'2026-06-30', serials:[], status:'damaged', loc:'LOC-QUAR-01' }
);
// Seed reason domains for the new flows (rendered generically by erp-md-reasons.html over DB.reasonDomains).
DB.reasonDomains.push(
  { id:'dispose', label:'Disposal / scrap', groupedBy:'Method', groups:[
    { key:'scrap',    label:'Scrap',     reasons:['Damaged beyond repair','Spoiled / contaminated','Failed QA','Pest / infestation'] },
    { key:'destroy',  label:'Destroy',   reasons:['Expired — destroy','Recall — destroy','Regulatory destruction','Client-instructed destruction'] },
    { key:'writeoff', label:'Write-off', reasons:['Shrinkage / unrecoverable','Lost in warehouse','Insurance write-off'] },
  ]},
  { id:'refuse', label:'Delivery refusal', groupedBy:'', groups:[
    { key:'all', label:'All refusals', reasons:['Expired on arrival','Damaged / unsafe load','Wrong goods delivered','Temperature excursion','Seal broken / tampered','No / wrong paperwork','Not ordered — no ASN','Client instruction to refuse'] },
  ]},
  { id:'rtv', label:'Return to vendor / client', groupedBy:'', groups:[
    { key:'all', label:'All RTV', reasons:['Defective — return to supplier','Recall — return to supplier','Expired — return to client','Wrong goods — return to supplier','Client recall / withdrawal','Over-delivery returned'] },
  ]},
  { id:'receipt', label:'Receipt condition', groupedBy:'Condition', groups:[
    { key:'hold',    label:'Hold for inspection', reasons:['Near-expiry — check','Visual defect — verify','Documentation pending','Awaiting QA sample'] },
    { key:'damaged', label:'Damaged at receipt',  reasons:['Crushed / broken','Temperature excursion','Seal broken / tampered','Wet / water damage','Contaminated / spoiled'] },
  ]}
);
// Seed: one pending disposal + one open RTV so the new screens demo immediately.
if (!DB.disposals.length) DB.disposals.push(
  { id:'DSP-7001', client:'C-ACME', site:'S-LYON', lpn:'LPN-00040', product:'P-1001', qty:40, method:'scrap',
    reason:'Damaged beyond repair', note:'Forklift puncture — whole plate', status:'pending', by:'Samer Merhi — Operator', created:'2026-06-18 14:20', approver:'', posted:'' }
);
if (!DB.rtvs.length) DB.rtvs.push(
  { id:'RTV-7001', client:'C-GLBX', site:'S-LYON', destType:'supplier', dest:'SUP-200', reason:'Recall — return to supplier',
    status:'open', created:'2026-06-18 15:00', by:'Benjamin Felix — Supervisor', shipped:'',
    lines:[ { lpn:'LPN-00005', product:'P-2001', qty:30, lot:'VX-71', expiry:'2026-07-15', serials:['SN-101…130'] } ] }
);

/* ---- Seed a few ASSIGNEES so the "My requests" filter demos non-empty in BOTH channels ----
   ERP current user = U-002 (Karim); PWA operator = U-003 (Lena). Most work stays UNASSIGNED ("Any").
   Only sets when the field is still absent, so re-running over a hydrated PWA snapshot is a no-op.
   [mock caveat] a returning PWA tab restores its own sessionStorage snapshot (taken before this seed
   existed) — hit "Reset demo data" once to pick the seeded assignees up, same as the putaway seeds. */
(function seedAssignees(){
  const setDoc = (coll, id, uid) => { const r=(DB[coll]||[]).find(x=>x.id===id); if (r && r.assignee==null) r.assignee=uid; };
  const setLpn = (id, uid) => { const l=lpnById(id); if (l && l.assignee==null) l.assignee=uid; };
  // document-backed queues
  setDoc('outbound','OUT-7001','U-003'); setDoc('outbound','OUT-7101','U-003'); setDoc('outbound','OUT-7102','U-002');
  setDoc('transfers','TRF-8002','U-002');
  setDoc('counts','CNT-9003','U-003');
  setDoc('physicals','PHY-7001','U-002');
  setDoc('returns','RET-9002','U-003');
  setDoc('rtvs','RTV-7001','U-002');
  setDoc('disposals','DSP-7001','U-003');
  setDoc('asns','ASN-3101','U-003');
  // LPN/pallet-backed queues (putaway = to-putaway plates; inspect = to-inspect plates)
  setLpn('LPN-00101','U-003'); setLpn('LPN-00102','U-002');
}());

/* ============================================================
   OIL & GAS CLIENTS (3PL) — added seed block.
   Three industrial clients (Technip Energies, Schlumberger, Yinson) operating out of the
   EXISTING Luanda DC (S-LYON) — NO new site (per the build decision: reuse Luanda). Adds: a global
   Oil & Gas product category; per-client DEDICATED heavy-duty storage areas at Luanda (D=Technip,
   E=Schlumberger, F=Yinson) + their bins (rig equipment is far heavier than the FMCG that Areas
   A/B are weight-capped for — a gate valve is 85 kg, a barite pallet ~5 t — and segregation keeps
   each client's stock in its own zone); suppliers/carrier/consignees; products that exercise the tracking
   flags realistically (bulk fasteners/gaskets = none; pipe/flange = lot/heat-number;
   equipment = serial; drilling/cementing chemicals = lot+expiry); and a full
   receive -> putaway -> stock-out chain (ASNs incl. a partial, to-putaway + available LPNs incl.
   an expired chemical + a to-inspect + a damaged plate, and outbound orders incl. a SHORT-CLOSE
   and a BACK-ORDER). Client–area segregation is ON (DB.settings.clientAreaSegregation=true): each O&G
   client's Area is owned, so cross-client putaway/move/transfer/restock is blocked (binSegregationOk).
   Idempotent: guarded on C-TCHP so a re-eval / hydrated PWA snapshot won't duplicate.
   ============================================================ */
(function seedOilAndGas(){
  if (DB.clients.some(c=>c.id==='C-TCHP')) return;   // already seeded

  // --- Global product category (joins the existing food/pharma taxonomy; catName/subCatName read it) ---
  DB.categories.push(
    { id:'CAT-OG', name:'Oil & Gas Equipment', subs:[
      { id:'SUB-RIG',   name:'Rig Construction & Structural' },
      { id:'SUB-VALVE', name:'Valves & Flow Control' },
      { id:'SUB-DRILL', name:'Drilling Tools & Equipment' },
      { id:'SUB-CHEM',  name:'Drilling & Cementing Chemicals' },
      { id:'SUB-ROT',   name:'Rotating & Marine Equipment' },
    ]}
  );

  // --- Per-client DEDICATED storage areas at Luanda (segregation is ON). Each O&G client gets its OWN Area +
  //     heavy bins, so binSegregationOk() refuses cross-client putaway / move / transfer-receive / returns-restock.
  //     (Existing Areas: A = shared, B = Globex-owned. Soyo Area C stays shared — a deliberate shared example.) ---
  const lyon = DB.sites.find(s=>s.id==='S-LYON');
  if (lyon && !lyon.areas.some(a=>a.code==='D')) lyon.areas.push(
    { code:'D', name:'Area D — Technip (Oil & Gas)',      preferredCategories:['CAT-OG'], preferredSubCategories:['SUB-RIG','SUB-VALVE'],  owningClient:'C-TCHP' },
    { code:'E', name:'Area E — Schlumberger (Oil & Gas)', preferredCategories:['CAT-OG'], preferredSubCategories:['SUB-DRILL','SUB-CHEM'], owningClient:'C-SLB' },
    { code:'F', name:'Area F — Yinson (Oil & Gas)',       preferredCategories:['CAT-OG'], preferredSubCategories:['SUB-ROT','SUB-VALVE'],  owningClient:'C-YIN' }
  );

  // --- Heavy-capacity storage bins, each assigned to its client's dedicated Area (D=Technip, E=SLB, F=Yinson). ---
  DB.locations.push(
    { id:'LOC-D01', site:'S-LYON', type:'storage', area:'D', path:{Floor:'1',Zone:'D',Aisle:'01',Rack:'R1',Bin:'B01'}, structured:'1-D-01-R1-B01', userRef:'Technip — valves / heavy',   status:'active', maxWeightKg:15000, maxUnits:3000, maxLpns:15 },
    { id:'LOC-D02', site:'S-LYON', type:'storage', area:'D', path:{Floor:'1',Zone:'D',Aisle:'01',Rack:'R1',Bin:'B02'}, structured:'1-D-01-R1-B02', userRef:'Technip — fasteners',        status:'active', maxWeightKg:10000, maxUnits:4000, maxLpns:12 },
    { id:'LOC-E01', site:'S-LYON', type:'storage', area:'E', path:{Floor:'1',Zone:'E',Aisle:'01',Rack:'R1',Bin:'B01'}, structured:'1-E-01-R1-B01', userRef:'SLB — drilling tools',       status:'active', maxWeightKg:8000,  maxUnits:2000, maxLpns:10 },
    { id:'LOC-E02', site:'S-LYON', type:'storage', area:'E', path:{Floor:'1',Zone:'E',Aisle:'01',Rack:'R1',Bin:'B02'}, structured:'1-E-01-R1-B02', userRef:'SLB — chemicals',           status:'active', maxWeightKg:12000, maxUnits:5000, maxLpns:12 },
    { id:'LOC-F01', site:'S-LYON', type:'storage', area:'F', path:{Floor:'1',Zone:'F',Aisle:'01',Rack:'R1',Bin:'B01'}, structured:'1-F-01-R1-B01', userRef:'Yinson — rotating / marine', status:'active', maxWeightKg:8000,  maxUnits:2000, maxLpns:10 },
    { id:'LOC-F02', site:'S-LYON', type:'storage', area:'F', path:{Floor:'1',Zone:'F',Aisle:'01',Rack:'R1',Bin:'B02'}, structured:'1-F-01-R1-B02', userRef:'Yinson — general',          status:'active', maxWeightKg:10000, maxUnits:4000, maxLpns:12 }
  );

  // --- Clients (owners of the stock; 3PL — operator never owns it). Mix of remainder policy. ---
  DB.clients.push(
    { id:'C-TCHP', name:'Technip Energies', legal:'Technip Energies N.V.',
      contact:'Élodie Garnier', email:'logistics@technipenergies.example', phone:'+33 1 47 78 0100',
      country:'France', status:'active', sites:['S-LYON'], allowBackorder:true },
    { id:'C-SLB', name:'Schlumberger', legal:'Schlumberger Limited (SLB)',
      contact:'Raj Patel', email:'supplychain@slb.example', phone:'+33 1 40 62 0200',
      country:'France', status:'active', sites:['S-LYON'], allowBackorder:false },
    { id:'C-YIN', name:'Yinson', legal:'Yinson Holdings Berhad',
      contact:'Tan Wei Ling', email:'ops@yinson.example', phone:'+60 3 2300 0300',
      country:'Malaysia', status:'active', sites:['S-LYON'], allowBackorder:true }
  );

  // --- Suppliers (GLOBAL master — inbound source on an ASN header). ---
  DB.suppliers.push(
    { id:'SUP-300', name:'Vallourec Tubes',      contact:'Pierre Lemoine', email:'export@vallourec.example', phone:'+33 1 49 09 0300', country:'France',        status:'active' },
    { id:'SUP-400', name:'NOV Inc.',             contact:'Mary Sullivan',  email:'orders@nov.example',       phone:'+1 713 555 0400',  country:'United States', status:'active' },
    { id:'SUP-500', name:'Cameron Flow Control', contact:'James Okoro',    email:'sales@cameron.example',    phone:'+1 281 555 0500',  country:'United States', status:'active' }
  );

  // --- Carrier (GLOBAL master — heavy-haul / project logistics for outbound dispatch). ---
  DB.carriers.push(
    { id:'CAR-HLT', name:'Heavy-Lift Project Logistics', scac:'HLPL', mode:'Road · Heavy haul', contact:'Project desk', phone:'+33 4 555 0600', status:'active' }
  );

  // --- Consignees (CLIENT-scoped ship-to points — yards / field bases / offshore supply bases). ---
  DB.consignees.push(
    { id:'CNE-TQ01', client:'C-TCHP', name:'Technip Fabrication Yard — Le Trait', address:'Quai de Seine',             city:'Le Trait',          country:'France',         contact:'Yard goods-in',         phone:'+33 2 555 0701',  status:'active' },
    { id:'CNE-TQ02', client:'C-TCHP', name:'Offshore Supply Base — Fos',          address:'Darse 2, Port de Fos',      city:'Fos-sur-Mer',       country:'France',         contact:'Quayside ops',          phone:'+33 4 555 0702',  status:'active' },
    { id:'CNE-SB01', client:'C-SLB',  name:'SLB Field Base — Lacq',               address:'Zone Industrielle',         city:'Lacq',              country:'France',         contact:'Base store',            phone:'+33 5 555 0703',  status:'active' },
    { id:'CNE-SB02', client:'C-SLB',  name:'Rig 12 — North Sea Wellsite',         address:'Block 22/4 — via Aberdeen', city:'Aberdeen',          country:'United Kingdom', contact:'Materials coordinator', phone:'+44 1224 555 0704', status:'active' },
    { id:'CNE-YN01', client:'C-YIN',  name:'FPSO Anna Nery — Marine Base',        address:'Porto do Açu',              city:'São João da Barra', country:'Brazil',         contact:'Marine logistics',      phone:'+55 22 555 0705', status:'active' },
    { id:'CNE-YN02', client:'C-YIN',  name:'Yinson Yard — Singapore',             address:'Tuas South Ave',            city:'Singapore',         country:'Singapore',      contact:'Yard receiving',        phone:'+65 6555 0706',   status:'active' }
  );

  // --- Products (client-scoped). Tracking profile mirrors real O&G material control:
  //     fasteners/gaskets = none; pipe/flange = lot (heat number); equipment = serial; chemicals = lot+expiry. ---
  DB.products.push(
    // Technip Energies — rig construction & structural
    { id:'P-TQ01', client:'C-TCHP', sku:'BOLT-M20-120', name:'Hex Bolt M20×120 Gr 8.8 (galv)',   uom:'each', barcode:'6021000000011', track:{lot:false,expiry:false,serial:false}, category:'CAT-OG', subCategory:'SUB-RIG',   weightKg:0.35, preferred:[{site:'S-LYON',mode:'area',ref:'D'}] },
    { id:'P-TQ02', client:'C-TCHP', sku:'FLG-6-900',    name:'Weld-Neck Flange 6" 900# A105',     uom:'each', barcode:'6021000000028', track:{lot:true,expiry:false,serial:false},  category:'CAT-OG', subCategory:'SUB-RIG',   weightKg:12,   preferred:[{site:'S-LYON',mode:'area',ref:'D'}] },
    { id:'P-TQ03', client:'C-TCHP', sku:'GV-6-900',     name:'Gate Valve 6" 900# (trunnion)',     uom:'each', barcode:'6021000000035', track:{lot:false,expiry:false,serial:true},  category:'CAT-OG', subCategory:'SUB-VALVE', weightKg:85,   preferred:[{site:'S-LYON',mode:'location',ref:'LOC-D01'}] },
    { id:'P-TQ04', client:'C-TCHP', sku:'RJG-R46',      name:'Ring-Joint Gasket R-46 (Inconel)',  uom:'each', barcode:'6021000000042', track:{lot:false,expiry:false,serial:false}, category:'CAT-OG', subCategory:'SUB-RIG',   weightKg:0.4,  preferred:[] },
    // Schlumberger — oilfield services
    { id:'P-SB01', client:'C-SLB',  sku:'BIT-PDC-8.5',  name:'PDC Drill Bit 8½"',                 uom:'each', barcode:'6022000000010', track:{lot:false,expiry:false,serial:true},  category:'CAT-OG', subCategory:'SUB-DRILL', weightKg:45,   preferred:[{site:'S-LYON',mode:'area',ref:'E'}] },
    { id:'P-SB02', client:'C-SLB',  sku:'BARITE-25',    name:'Drilling Mud Barite (25 kg bag)',   uom:'bag',  barcode:'6022000000027', track:{lot:true,expiry:false,serial:false},  category:'CAT-OG', subCategory:'SUB-CHEM',  weightKg:25,   preferred:[{site:'S-LYON',mode:'area',ref:'E'}] },
    { id:'P-SB03', client:'C-SLB',  sku:'MWD-SUB',      name:'MWD Sensor Sub',                    uom:'each', barcode:'6022000000034', track:{lot:false,expiry:false,serial:true},  category:'CAT-OG', subCategory:'SUB-DRILL', weightKg:60,   preferred:[] },
    { id:'P-SB04', client:'C-SLB',  sku:'CEM-RET-20',   name:'Cement Retarder Additive (20 kg)',  uom:'bag',  barcode:'6022000000041', track:{lot:true,expiry:true,serial:false},   category:'CAT-OG', subCategory:'SUB-CHEM',  weightKg:20,   preferred:[{site:'S-LYON',mode:'area',ref:'E'}] },
    // Yinson — FPSO / marine
    { id:'P-YN01', client:'C-YIN',  sku:'IMP-CRNI',     name:'Centrifugal Pump Impeller (CrNi)',  uom:'each', barcode:'6023000000019', track:{lot:false,expiry:false,serial:true},  category:'CAT-OG', subCategory:'SUB-ROT',   weightKg:28,   preferred:[{site:'S-LYON',mode:'area',ref:'F'}] },
    { id:'P-YN02', client:'C-YIN',  sku:'HOSE-1-10M',   name:'Hydraulic Hose Assembly 1" (10 m)', uom:'each', barcode:'6023000000026', track:{lot:false,expiry:false,serial:false}, category:'CAT-OG', subCategory:'SUB-ROT',   weightKg:6,    preferred:[] },
    { id:'P-YN03', client:'C-YIN',  sku:'GKT-MAR-SET',  name:'Marine Gasket Set (topside)',       uom:'each', barcode:'6023000000033', track:{lot:false,expiry:false,serial:false}, category:'CAT-OG', subCategory:'SUB-RIG',   weightKg:1.2,  preferred:[] },
    { id:'P-YN04', client:'C-YIN',  sku:'CV-2',         name:'Topside Control Valve 2"',          uom:'each', barcode:'6023000000040', track:{lot:false,expiry:false,serial:true},  category:'CAT-OG', subCategory:'SUB-VALVE', weightKg:22,   preferred:[{site:'S-LYON',mode:'area',ref:'F'}] }
  );

  // --- LPNs: available stock (Area D) + to-putaway (inbound staging) + an expired chemical + a to-inspect + a damaged.
  //     Serial-tracked plates carry a range token whose expanded count == qty (validateSerials checks this on issue). ---
  DB.lpns.push(
    // Technip Energies
    { id:'LPN-00200', client:'C-TCHP', site:'S-LYON', product:'P-TQ01', qty:1000, lot:'',        expiry:'', serials:[],                 status:'available',  loc:'LOC-D02' },
    { id:'LPN-00201', client:'C-TCHP', site:'S-LYON', product:'P-TQ02', qty:24,   lot:'HT-7741', expiry:'', serials:[],                 status:'available',  loc:'LOC-D01' },
    { id:'LPN-00202', client:'C-TCHP', site:'S-LYON', product:'P-TQ03', qty:6,    lot:'',        expiry:'', serials:['GV6-0001…0006'], status:'available',  loc:'LOC-D01' },
    { id:'LPN-00203', client:'C-TCHP', site:'S-LYON', product:'P-TQ01', qty:500,  lot:'',        expiry:'', serials:[],                 status:'to-putaway', loc:'LOC-WAIT-01' },
    { id:'LPN-00204', client:'C-TCHP', site:'S-LYON', product:'P-TQ04', qty:200,  lot:'',        expiry:'', serials:[],                 status:'to-putaway', loc:'LOC-WAIT-01' },
    // Schlumberger
    { id:'LPN-00210', client:'C-SLB',  site:'S-LYON', product:'P-SB01', qty:8,    lot:'',        expiry:'',           serials:['BIT-0001…0008'], status:'available',  loc:'LOC-E01' },
    { id:'LPN-00211', client:'C-SLB',  site:'S-LYON', product:'P-SB02', qty:200,  lot:'BAR-2405', expiry:'',          serials:[],                status:'available',  loc:'LOC-E02' },
    { id:'LPN-00212', client:'C-SLB',  site:'S-LYON', product:'P-SB04', qty:100,  lot:'CEM-2403', expiry:'2027-02-28', serials:[],                status:'available',  loc:'LOC-E02' },
    // expired chemical demo (expiry < WMS_TODAY 2026-06-15): physically present + 'available' but excluded from FEFO/issue.
    { id:'LPN-00215', client:'C-SLB',  site:'S-LYON', product:'P-SB04', qty:20,   lot:'CEM-2208', expiry:'2026-05-31', serials:[],                status:'available',  loc:'LOC-E02' },
    { id:'LPN-00213', client:'C-SLB',  site:'S-LYON', product:'P-SB03', qty:4,    lot:'',        expiry:'',           serials:['MWD-0001…0004'], status:'to-putaway', loc:'LOC-WAIT-01' },
    { id:'LPN-00214', client:'C-SLB',  site:'S-LYON', product:'P-SB02', qty:120,  lot:'BAR-2406', expiry:'',          serials:[],                status:'to-putaway', loc:'LOC-WAIT-01' },
    // Yinson
    { id:'LPN-00220', client:'C-YIN',  site:'S-LYON', product:'P-YN01', qty:10,   lot:'', expiry:'', serials:['IMP-0001…0010'], status:'available',  loc:'LOC-F01' },
    { id:'LPN-00221', client:'C-YIN',  site:'S-LYON', product:'P-YN02', qty:50,   lot:'', expiry:'', serials:[],                status:'available',  loc:'LOC-F01' },
    { id:'LPN-00222', client:'C-YIN',  site:'S-LYON', product:'P-YN04', qty:12,   lot:'', expiry:'', serials:['CV2-0001…0012'], status:'available',  loc:'LOC-F01' },
    { id:'LPN-00223', client:'C-YIN',  site:'S-LYON', product:'P-YN03', qty:80,   lot:'', expiry:'', serials:[],                status:'to-putaway', loc:'LOC-WAIT-01' },
    { id:'LPN-00224', client:'C-YIN',  site:'S-LYON', product:'P-YN01', qty:6,    lot:'', expiry:'', serials:['IMP-0101…0106'], status:'to-inspect', loc:'LOC-WAIT-01' },
    { id:'LPN-00225', client:'C-YIN',  site:'S-LYON', product:'P-YN02', qty:5,    lot:'', expiry:'', serials:[],                status:'damaged',    loc:'LOC-QUAR-01' }
  );

  // --- ASNs (inbound advance ship notices): open + a partial (status DERIVED via asnStatus). ---
  DB.asns.push(
    { id:'ASN-3201', client:'C-TCHP', site:'S-LYON', supplier:'SUP-300', lines:[
        { product:'P-TQ02', qty:50, received:0 }, { product:'P-TQ03', qty:6, received:0 } ] },
    { id:'ASN-3202', client:'C-SLB',  site:'S-LYON', supplier:'SUP-400', lines:[
        { product:'P-SB01', qty:8, received:8 }, { product:'P-SB02', qty:400, received:200 } ] },   // -> partial
    { id:'ASN-3203', client:'C-YIN',  site:'S-LYON', supplier:'SUP-500', lines:[
        { product:'P-YN04', qty:12, received:0 }, { product:'P-YN01', qty:10, received:0 } ] },
    { id:'ASN-3204', client:'C-TCHP', site:'S-LYON', supplier:'SUP-300', lines:[
        { product:'P-TQ01', qty:1000, received:0 } ] }
  );

  // --- Outbound orders: a simple pick, a serial pick, a pre-allocated order, a SHORT-CLOSE (SLB) and a BACK-ORDER (Technip). ---
  DB.outbound.push(
    { id:'OUT-7201', client:'C-TCHP', site:'S-LYON', shipTo:'CNE-TQ01', ref:'PO-TCHP-001', created:'2026-06-18',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TQ01', qty:600, shipped:0, alloc:[] } ] },
    { id:'OUT-7202', client:'C-SLB',  site:'S-LYON', shipTo:'CNE-SB02', ref:'PO-SLB-118', created:'2026-06-18',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-SB01', qty:3, shipped:0, alloc:[] } ] },
    { id:'OUT-7203', client:'C-YIN',  site:'S-LYON', shipTo:'CNE-YN01', ref:'PO-YIN-204', created:'2026-06-17',
      status:'allocated', fullStockOut:false, shipments:[], lines:[
        { product:'P-YN01', qty:4, shipped:0, alloc:[ { lpn:'LPN-00220', lot:'', expiry:'', from:'LOC-F01', qty:4, picked:0, serials:'IMP-0001…0004' } ] } ] },
    // SLB allowBackorder=false: orders 500 barite, only 200 available (LPN-00214's 120 is still to-putaway) -> SHORT-CLOSE demo.
    { id:'OUT-7204', client:'C-SLB',  site:'S-LYON', shipTo:'CNE-SB01', ref:'PO-SLB-120', created:'2026-06-18',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-SB02', qty:500, shipped:0, alloc:[] } ] },
    // Technip allowBackorder=true: orders 40 flanges, only 24 available -> BACK-ORDER demo (16 stays open).
    { id:'OUT-7205', client:'C-TCHP', site:'S-LYON', shipTo:'CNE-TQ02', ref:'PO-TCHP-002', created:'2026-06-18',
      status:'open', fullStockOut:false, shipments:[], lines:[ { product:'P-TQ02', qty:40, shipped:0, alloc:[] } ] }
  );

  // --- A few audit txns so Reports show O&G history (a receive + putaway pair, and the SLB partial receive). ---
  DB.txns.push(
    { id:'TXN-1101', ts:'2026-06-17 08:30', type:'receive', lpn:'LPN-00210', product:'P-SB01', qty:8,   from:'',            to:'LOC-WAIT-01', site:'S-LYON', user:'Benjamin Felix', ref:'GRN-4201', note:'Drill bits received (SLB)' },
    { id:'TXN-1102', ts:'2026-06-17 10:15', type:'putaway', lpn:'LPN-00210', product:'P-SB01', qty:8,   from:'LOC-WAIT-01', to:'LOC-E01',     site:'S-LYON', user:'Samer Merhi',    ref:'',         note:'Directed putaway (Area E)' },
    { id:'TXN-1103', ts:'2026-06-17 11:40', type:'receive', lpn:'LPN-00211', product:'P-SB02', qty:200, from:'',            to:'LOC-E02',     site:'S-LYON', user:'Samer Merhi',    ref:'GRN-4202', note:'Barite partial receipt (200/400)' }
  );
}());
