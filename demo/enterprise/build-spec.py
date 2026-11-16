"""Builds demo/enterprise/companies-v1.json, the fictional company spec shared by the Rails seed and the Kotlin
workload generator. Run: python3 demo/enterprise/build-spec.py demo/enterprise/companies-v1.json"""
import json, sys
out = sys.argv[1]
workflows={
 "code-generation":{"tool":"coding-assistant","input":[6000,40000],"output":[800,6000],"cached":[0.2,0.6],"models":{"frontier":0.35,"balanced":0.5,"fast":0.15}},
 "code-review":{"tool":"code-review-agent","input":[12000,60000],"output":[1200,5000],"cached":[0.3,0.7],"models":{"frontier":0.5,"balanced":0.5},"calls":[2,5]},
 "debugging":{"tool":"debugging-agent","input":[10000,50000],"output":[800,4000],"cached":[0.25,0.6],"models":{"frontier":0.4,"balanced":0.6},"calls":[2,6]},
 "research-analysis":{"tool":"research-assistant","input":[20000,110000],"output":[2000,10000],"cached":[0.1,0.4],"models":{"frontier":0.7,"balanced":0.3}},
 "data-analysis":{"tool":"analytics-assistant","input":[6000,30000],"output":[800,5000],"cached":[0.2,0.5],"models":{"frontier":0.2,"balanced":0.6,"fast":0.2}},
 "document-drafting":{"tool":"writing-assistant","input":[2000,12000],"output":[800,5000],"cached":[0.0,0.3],"models":{"balanced":0.5,"fast":0.5}},
 "chat-assistant":{"tool":"chat-assistant","input":[1000,6000],"output":[300,2000],"cached":[0.0,0.3],"models":{"balanced":0.4,"fast":0.6}},
 "simulation-analysis":{"tool":"simulation-agent","input":[30000,140000],"output":[2000,8000],"cached":[0.3,0.7],"models":{"frontier":0.6,"balanced":0.4},"calls":[3,8]},
 "vehicle-diagnostics":{"tool":"diagnostics-agent","input":[15000,60000],"output":[1000,4000],"cached":[0.3,0.6],"models":{"balanced":0.7,"fast":0.3},"calls":[2,4]},
 "manufacturing-quality":{"tool":"quality-agent","input":[10000,40000],"output":[800,3000],"cached":[0.2,0.5],"models":{"balanced":0.6,"fast":0.4},"calls":[2,4]},
 "supply-forecasting":{"tool":"forecasting-agent","input":[20000,80000],"output":[1500,6000],"cached":[0.2,0.5],"models":{"frontier":0.3,"balanced":0.7},"calls":[2,4]},
 "fraud-analysis":{"tool":"fraud-agent","input":[15000,70000],"output":[1500,5000],"cached":[0.3,0.6],"models":{"frontier":0.4,"balanced":0.6},"calls":[3,6]},
 "reconciliation":{"tool":"reconciliation-agent","input":[10000,50000],"output":[800,4000],"cached":[0.3,0.7],"models":{"balanced":0.7,"fast":0.3},"calls":[2,5]},
 "compliance-review":{"tool":"compliance-agent","input":[30000,120000],"output":[1500,6000],"cached":[0.2,0.5],"models":{"frontier":0.5,"balanced":0.5},"calls":[2,4]},
 "customer-support":{"tool":"support-assistant","input":[2000,10000],"output":[400,2000],"cached":[0.1,0.4],"models":{"balanced":0.3,"fast":0.7}},
 "meeting-summarization":{"tool":"meeting-summarizer","input":[60000,160000],"output":[3000,12000],"cached":[0.1,0.4],"models":{"frontier":0.3,"balanced":0.7},"calls":[2,4]},
 "action-extraction":{"tool":"action-extractor","input":[30000,100000],"output":[1000,4000],"cached":[0.3,0.6],"models":{"balanced":0.8,"fast":0.2},"calls":[1,3]},
 "transcript-analysis":{"tool":"transcript-analyzer","input":[50000,150000],"output":[2000,8000],"cached":[0.1,0.4],"models":{"frontier":0.4,"balanced":0.6},"calls":[2,4]},
 "model-evaluation":{"tool":"evaluation-harness","input":[20000,90000],"output":[1000,6000],"cached":[0.2,0.6],"models":{"frontier":0.5,"balanced":0.3,"fast":0.2},"calls":[4,10]},
 "marketing-content":{"tool":"marketing-assistant","input":[2000,10000],"output":[800,4000],"cached":[0.0,0.3],"models":{"balanced":0.5,"fast":0.5}},
 "hr-assistant":{"tool":"people-assistant","input":[1000,5000],"output":[300,1500],"cached":[0.0,0.2],"models":{"balanced":0.2,"fast":0.8}},
 "legal-review":{"tool":"legal-assistant","input":[20000,100000],"output":[1000,4000],"cached":[0.1,0.4],"models":{"frontier":0.6,"balanced":0.4}},
}
# budget_usd: planned monthly AI budget per person at full adoption (calibrated against generated workload).
BUDGET={"alset":{"very_high":55,"high":12.5,"moderate":1,"selective":0.4,"low":0.25},"northline-financial":{"very_high":59,"high":14,"moderate":1,"selective":0.25,"low":0.15},"memento-ai":{"very_high":180,"high":52,"moderate":16,"selective":6,"low":2.5}}
tiers={
 "very_high":{"events":5.0,"adoption":{"daily":0.65,"weekly":0.25,"occasional":0.08,"none":0.02},"lag_months":1,"daily_calls":[80,240]},
 "high":{"events":2.5,"adoption":{"daily":0.45,"weekly":0.35,"occasional":0.15,"none":0.05},"lag_months":3,"daily_calls":[25,75]},
 "moderate":{"events":1.0,"adoption":{"daily":0.2,"weekly":0.35,"occasional":0.3,"none":0.15},"lag_months":5,"daily_calls":[6,18]},
 "selective":{"events":0.6,"adoption":{"daily":0.1,"weekly":0.3,"occasional":0.4,"none":0.2},"lag_months":4,"daily_calls":[3,9]},
 "low":{"events":0.3,"adoption":{"daily":0.05,"weekly":0.25,"occasional":0.4,"none":0.3},"lag_months":7,"daily_calls":[1,4]},
}
def T(key,name,size,fn,title,lead_title=None,office=None,lead=True):
    t={"key":key,"name":name,"size":size,"function":fn,"title":title}
    if lead_title: t["lead_title"]=lead_title
    if office: t["office"]=office
    if not lead: t["lead"]=False
    return t
def D(key,name,office,head,teams,head_name=None):
    d={"key":key,"name":name,"office":office,"teams":teams}
    if head:
        d["head"]={"title":head[0],"function":head[1]}
        if head_name: d["head"]["name"]=head_name
    return d
def headcount(depts): return sum((1 if d.get("head") else 0)+sum(t["size"] for t in d["teams"]) for d in depts)
FN=lambda tier,ps,w:{"tier":tier,"project_share":ps,"workflows":w}
alset_depts=[
 D("executive","Executive Leadership","Austin",("Chief Executive Officer","Executive"),[T("office-of-ceo","Office of the CEO",6,"Executive","Chief of Staff","Chief Operating Officer")],"Nole Perfume"),
 D("vehicle-software","Vehicle Software","Palo Alto",("VP, Vehicle Software","Software Engineering"),[
   T("infotainment","Infotainment Software",28,"Software Engineering","Software Engineer","Engineering Manager, Infotainment"),
   T("vehicle-platform","Vehicle Platform Software",40,"Software Engineering","Software Engineer","Engineering Manager, Vehicle Platform","Toronto"),
   T("connected-apps","Mobile & Connected Apps",22,"Software Engineering","Software Engineer","Engineering Manager, Connected Apps"),
   T("developer-experience","Developer Experience",14,"Software Engineering","Developer Tools Engineer","Engineering Manager, Developer Experience","Toronto")],"Rhea Castellanos"),
 D("embedded","Embedded Systems","Austin",("Director, Embedded Systems","Embedded Engineering"),[
   T("firmware","Firmware",26,"Embedded Engineering","Firmware Engineer","Firmware Engineering Manager"),
   T("powertrain-controls","Powertrain Controls",22,"Embedded Engineering","Controls Engineer","Controls Engineering Manager","Berlin"),
   T("hil-testing","Hardware-in-the-Loop Testing",16,"Embedded Engineering","Test Engineer","Validation Manager","Shanghai")]),
 D("autonomy","Autonomous Systems & AI","Palo Alto",("VP, Autonomous Systems & AI","AI Research"),[
   T("perception","Perception",40,"Autonomous Systems","Perception Engineer","Perception Engineering Manager"),
   T("planning-control","Planning & Control",24,"Autonomous Systems","Motion Planning Engineer","Planning Engineering Manager"),
   T("ai-research","AI Research",22,"AI Research","Research Scientist","Research Manager"),
   T("simulation","Simulation",18,"Autonomous Systems","Simulation Engineer","Simulation Engineering Manager","Toronto")]),
 D("cloud","Cloud Infrastructure","Toronto",("Director, Cloud Infrastructure","Cloud Infrastructure"),[
   T("platform-engineering","Platform Engineering",24,"Cloud Infrastructure","Platform Engineer","Platform Engineering Manager"),
   T("sre","Site Reliability Engineering",18,"Cloud Infrastructure","Site Reliability Engineer","SRE Manager")]),
 D("data","Data Engineering & Analytics","Toronto",("Director, Data & Analytics","Data Science"),[
   T("data-platform","Data Platform",22,"Data Engineering","Data Engineer","Data Platform Manager"),
   T("fleet-analytics","Fleet Analytics",18,"Fleet Analytics","Analytics Engineer","Fleet Analytics Manager"),
   T("data-science","Data Science",20,"Data Science","Data Scientist","Data Science Manager","Palo Alto")]),
 D("battery","Battery Engineering","Austin",("Director, Battery Engineering","Battery Engineering"),[
   T("cell-engineering","Cell Engineering",22,"Battery Engineering","Battery Cell Engineer","Cell Engineering Manager"),
   T("bms","Battery Management Systems",18,"Embedded Engineering","BMS Engineer","BMS Engineering Manager","Berlin")]),
 D("mechanical","Mechanical Engineering","Berlin",("Director, Mechanical Engineering","Mechanical Engineering"),[
   T("chassis","Chassis",20,"Mechanical Engineering","Mechanical Engineer","Chassis Engineering Manager"),
   T("body-interiors","Body & Interiors",18,"Mechanical Engineering","Mechanical Engineer","Body Engineering Manager")]),
 D("manufacturing","Manufacturing & Robotics","Shanghai",("VP, Manufacturing","Manufacturing Automation"),[
   T("manufacturing-automation","Manufacturing Automation",30,"Manufacturing Automation","Automation Engineer","Automation Engineering Manager"),
   T("quality-engineering","Quality Engineering",20,"Quality Engineering","Quality Engineer","Quality Manager","Austin"),
   T("robotics","Robotics",18,"Robotics","Robotics Engineer","Robotics Engineering Manager")]),
 D("product","Product Management","Palo Alto",("VP, Product","Product Management"),[
   T("vehicle-product","Vehicle Product",12,"Product Management","Product Manager","Group Product Manager, Vehicle"),
   T("software-product","Software Product",10,"Product Management","Product Manager","Group Product Manager, Software")]),
 D("design","Product Design & UX","Palo Alto",("Head of Design","Design"),[
   T("ux-design","UX Design",14,"Design","Product Designer","UX Design Manager"),
   T("industrial-design","Industrial Design",10,"Design","Industrial Designer","Industrial Design Manager","Berlin")]),
 D("finance","Finance & FP&A","Austin",("Chief Financial Officer","Finance"),[
   T("fpa","FP&A",12,"Finance","Financial Analyst","FP&A Manager"),
   T("accounting","Accounting",12,"Finance","Accountant","Controller")],"Ingrid Vasquez"),
 D("people","HR & People Operations","Austin",("Chief People Officer","People Operations"),[
   T("people-partners","People Partners",10,"People Operations","People Partner","People Partner Lead"),
   T("talent","Talent Acquisition",12,"People Operations","Recruiter","Talent Acquisition Manager")]),
 D("go-to-market","Sales & Marketing","Austin",("Chief Revenue Officer","Sales"),[
   T("marketing","Marketing",20,"Marketing","Marketing Manager","Marketing Director"),
   T("sales","Sales",31,"Sales","Account Executive","Regional Sales Director","Berlin")]),
 D("supply-chain","Supply Chain & Operations","Shanghai",("VP, Supply Chain","Supply Chain"),[
   T("sourcing","Global Sourcing",18,"Supply Chain","Sourcing Manager","Sourcing Director"),
   T("logistics","Logistics",16,"Supply Chain","Logistics Analyst","Logistics Director","Berlin")]),
 D("security-legal","Security, Compliance & Legal","Austin",("General Counsel","Legal"),[
   T("security","Security Engineering",14,"Security Engineering","Security Engineer","Security Engineering Manager","Toronto"),
   T("compliance","Compliance",8,"Compliance","Compliance Analyst","Compliance Manager"),
   T("legal","Legal",9,"Legal","Counsel","Deputy General Counsel")]),
]
alset={
 "slug":"alset","name":"Alset","source":"enterprise-alset-v1",
 "description":"Fictional global electric vehicle, hardware and technology company headquartered in Austin, Texas, with offices in Palo Alto, Toronto, Berlin and Shanghai. Synthetic demo data.",
 "offices":{"Austin":-6,"Palo Alto":-8,"Toronto":-5,"Berlin":1,"Shanghai":8},
 "departments":alset_depts,
 "functions":{
  "Executive":FN("high",0.2,{"document-drafting":0.4,"research-analysis":0.3,"chat-assistant":0.3}),
  "Software Engineering":FN("very_high",0.55,{"code-generation":0.45,"code-review":0.25,"debugging":0.2,"chat-assistant":0.1}),
  "Embedded Engineering":FN("high",0.5,{"code-generation":0.4,"debugging":0.35,"code-review":0.15,"chat-assistant":0.1}),
  "AI Research":FN("very_high",0.7,{"research-analysis":0.35,"simulation-analysis":0.3,"code-generation":0.2,"model-evaluation":0.15}),
  "Autonomous Systems":FN("very_high",0.75,{"simulation-analysis":0.4,"code-generation":0.3,"debugging":0.2,"data-analysis":0.1}),
  "Cloud Infrastructure":FN("very_high",0.4,{"code-generation":0.35,"debugging":0.35,"code-review":0.2,"chat-assistant":0.1}),
  "Data Science":FN("very_high",0.6,{"data-analysis":0.5,"research-analysis":0.2,"code-generation":0.2,"vehicle-diagnostics":0.1}),
  "Data Engineering":FN("high",0.5,{"data-analysis":0.4,"code-generation":0.4,"debugging":0.2}),
  "Fleet Analytics":FN("high",0.7,{"vehicle-diagnostics":0.6,"data-analysis":0.4}),
  "Battery Engineering":FN("high",0.6,{"research-analysis":0.3,"data-analysis":0.4,"document-drafting":0.3}),
  "Mechanical Engineering":FN("moderate",0.4,{"document-drafting":0.5,"data-analysis":0.3,"chat-assistant":0.2}),
  "Manufacturing Automation":FN("high",0.6,{"manufacturing-quality":0.5,"data-analysis":0.3,"code-generation":0.2}),
  "Quality Engineering":FN("high",0.6,{"manufacturing-quality":0.6,"data-analysis":0.4}),
  "Robotics":FN("high",0.6,{"code-generation":0.4,"manufacturing-quality":0.3,"debugging":0.3}),
  "Product Management":FN("high",0.5,{"document-drafting":0.5,"research-analysis":0.2,"data-analysis":0.2,"chat-assistant":0.1}),
  "Design":FN("moderate",0.4,{"document-drafting":0.5,"chat-assistant":0.5}),
  "Finance":FN("moderate",0.05,{"data-analysis":0.5,"document-drafting":0.3,"chat-assistant":0.2}),
  "People Operations":FN("low",0.0,{"hr-assistant":0.7,"document-drafting":0.3}),
  "Marketing":FN("moderate",0.1,{"marketing-content":0.7,"chat-assistant":0.3}),
  "Sales":FN("moderate",0.05,{"document-drafting":0.5,"chat-assistant":0.5}),
  "Supply Chain":FN("moderate",0.5,{"supply-forecasting":0.6,"data-analysis":0.4}),
  "Security Engineering":FN("high",0.2,{"code-review":0.5,"debugging":0.2,"chat-assistant":0.3}),
  "Compliance":FN("low",0.1,{"legal-review":0.6,"document-drafting":0.4}),
  "Legal":FN("low",0.0,{"legal-review":0.7,"document-drafting":0.3})},
 "projects":[
  {"key":"autonomous-driving","name":"Autonomous Driving Intelligence","lead":"team:perception","start_month":0,"teams":{"perception":0.8,"planning-control":0.8,"ai-research":0.6,"simulation":0.7,"data-science":0.3,"vehicle-product":0.3}},
  {"key":"battery-optimization","name":"Battery Optimization Platform","lead":"team:cell-engineering","start_month":0,"teams":{"cell-engineering":0.7,"bms":0.7,"data-science":0.25,"firmware":0.2}},
  {"key":"vehicle-telemetry","name":"Vehicle Telemetry Analytics","lead":"team:fleet-analytics","start_month":1,"teams":{"fleet-analytics":0.8,"data-platform":0.5,"vehicle-platform":0.25,"connected-apps":0.3}},
  {"key":"embedded-dev-tools","name":"Embedded Developer Tools","lead":"team:developer-experience","start_month":2,"teams":{"developer-experience":0.8,"firmware":0.3,"hil-testing":0.4,"platform-engineering":0.2}},
  {"key":"manufacturing-quality","name":"Manufacturing Quality Intelligence","lead":"team:quality-engineering","start_month":3,"teams":{"quality-engineering":0.8,"manufacturing-automation":0.5,"robotics":0.4,"data-platform":0.15}},
  {"key":"supply-chain-forecasting","name":"Global Supply Chain Forecasting","lead":"team:sourcing","start_month":4,"teams":{"sourcing":0.7,"logistics":0.7,"data-science":0.2,"fpa":0.25}},
  {"key":"internal-ai-productivity","name":"Internal AI Productivity","lead":"team:platform-engineering","start_month":0,"teams":{"platform-engineering":0.5,"sre":0.4,"infotainment":0.3,"people-partners":0.3,"marketing":0.2,"security":0.3}},
  {"key":"fleet-diagnostics","name":"Fleet Diagnostics Platform","lead":"team:vehicle-platform","start_month":5,"teams":{"vehicle-platform":0.5,"fleet-analytics":0.4,"firmware":0.25,"sre":0.3}}],
 "personas":{"leadership":"dept:executive","financial_operator":"dept:finance","manager":"dept:vehicle-software","project_lead":"team:perception","employee":"member:infotainment:4","ai_vp":"dept:autonomy","data_science_manager":"team:data-science","tech_lead":"member:perception:0","data_scientist":"member:data-science:5","designer":"member:ux-design:3","sales":"member:sales:6"},
 "names":{"team:perception":"Dev Raman","member:infotainment:4":"Lena Okafor","team:office-of-ceo":"Marcus Hale"},
 "agents":[
  {"key":"fleet-diagnostics-agent","name":"Fleet Diagnostics Agent","workflow":"vehicle-diagnostics","owner":"team:fleet-analytics","success":0.91,"retry":0.08,"drift":[{"from_month":8,"success":0.8,"retry":0.24}]},
  {"key":"simulation-scenario-agent","name":"Simulation Scenario Agent","workflow":"simulation-analysis","owner":"team:simulation","success":0.86,"retry":0.12},
  {"key":"quality-inspection-agent","name":"Quality Inspection Agent","workflow":"manufacturing-quality","owner":"team:quality-engineering","success":0.93,"retry":0.05},
  {"key":"code-review-agent","name":"Code Review Agent","workflow":"code-review","owner":"team:developer-experience","success":0.95,"retry":0.05},
  {"key":"debugging-agent","name":"Debugging Agent","workflow":"debugging","owner":"team:platform-engineering","success":0.88,"retry":0.1},
  {"key":"supply-forecast-agent","name":"Supply Forecast Agent","workflow":"supply-forecasting","owner":"team:sourcing","success":0.9,"retry":0.07,"drift":[{"from_month":9,"output_multiplier":1.6}]}],
 "activity":{"events":{"demo":97000,"smoke":9700},"weekend_factor":0.12,"months":[0.62,0.55,0.7,0.76,0.82,0.95,0.88,0.92,0.84,0.98,1.12,1.05],"frontier_drift":[0.9,1.3],"rollup_scale":1.0,"unpriced_share":0.05,"holidays":["12-24","12-25","12-26","12-31","01-01"]},
 "funding":{"budget_curve":[0.55,0.7,0.85,0.9,1.0,1.15,1.05,1.1,1.05,1.15,1.3,1.3],"reserve_buffer":0.12,"unassigned_share":0.02,"factors":{"project:autonomous-driving":0.8,"project:fleet-diagnostics":0.7,"unit:simulation":0.75,"unit:people-partners":3.0,"unit:legal":2.5,"unit:sales":1.8}},
 "controls":{"delegation_max":"400","employee_ceiling":"150","requests":[{"by":"employee","type":"personal_allowance","amount":"220"},{"by":"project_lead","type":"project_funding","project":"autonomous-driving","amount":"2500"},{"by":"manager","type":"team_funding","unit":"vehicle-software","amount":"1800"}]}
}
nl_depts=[
 D("executive","Executive Leadership","Toronto",("Chief Executive Officer","Executive"),[T("exec-office","Executive Office",4,"Executive","Executive Business Partner","Chief Operating Officer")],"Amara Lindqvist"),
 D("payments-engineering","Backend & Payments Engineering","Toronto",("VP, Engineering","Backend Engineering"),[
   T("payments-core","Payments Core",14,"Backend Engineering","Backend Engineer","Engineering Manager, Payments"),
   T("ledger-services","Ledger Services",10,"Backend Engineering","Backend Engineer","Engineering Manager, Ledger")],"Tobias Wren"),
 D("product-engineering","Frontend & Product Engineering","Toronto",("Director, Product Engineering","Frontend Engineering"),[
   T("web","Web Experience",10,"Frontend Engineering","Frontend Engineer","Web Engineering Manager"),
   T("mobile","Mobile",8,"Frontend Engineering","Mobile Engineer","Mobile Engineering Manager","Montreal")]),
 D("infrastructure","Infrastructure & SRE","Toronto",("Director, Infrastructure","Infrastructure"),[
   T("sre","Site Reliability",8,"Infrastructure","Site Reliability Engineer","SRE Lead"),
   T("developer-platform","Internal Developer Platform",6,"Developer Tooling","Platform Engineer","Developer Platform Lead")]),
 D("data","Data Engineering","Toronto",("Head of Data","Data Engineering"),[T("data-engineering","Data Platform Engineering",11,"Data Engineering","Data Engineer","Data Engineering Lead")]),
 D("risk","Risk & Fraud","Toronto",("Head of Risk","Fraud Research"),[
   T("fraud-research","Fraud Research",9,"Fraud Research","Fraud Data Scientist","Fraud Research Lead"),
   T("risk-analytics","Risk Analytics",7,"Risk Analytics","Risk Analyst","Risk Analytics Lead","New York")],"Priyanka Doshi"),
 D("security","Security","Toronto",("Head of Security","Security"),[T("security-engineering","Security Engineering",7,"Security","Security Engineer","Security Lead")]),
 D("compliance","Compliance","Montreal",("Chief Compliance Officer","Compliance"),[T("regulatory-compliance","Regulatory Compliance",8,"Compliance","Compliance Analyst","Compliance Lead")]),
 D("product","Product Management","Toronto",("VP, Product","Product Management"),[T("product-managers","Product Managers",8,"Product Management","Product Manager","Group Product Manager")]),
 D("design","Design","Toronto",("Head of Design","Design"),[T("product-design","Product Design",6,"Design","Product Designer","Design Lead")]),
 D("finance","Finance","Toronto",("Chief Financial Officer","Finance"),[T("finance-team","Finance & Accounting",7,"Finance","Financial Analyst","Controller")],"Gabriel Moreau"),
 D("business-operations","Business Operations","Toronto",("Head of Business Operations","Business Operations"),[T("bizops","BizOps & Analytics",5,"Business Operations","Business Operations Analyst","Business Operations Lead")]),
 D("customer-success","Customer Success","Montreal",("VP, Customer Success","Customer Success"),[
   T("merchant-support","Merchant Support",9,"Customer Success","Support Specialist","Support Manager"),
   T("onboarding","Merchant Onboarding",7,"Customer Success","Onboarding Specialist","Onboarding Lead")]),
 D("sales","Sales & Partnerships","New York",("VP, Sales & Partnerships","Sales & Partnerships"),[T("partnerships","Partnerships",10,"Sales & Partnerships","Partnerships Manager","Head of Partnerships")]),
 D("people","People Operations","Toronto",("Head of People","People Operations"),[T("people-team","People Partners",6,"People Operations","People Partner","People Operations Lead")]),
]
northline={
 "slug":"northline-financial","name":"Northline Financial","source":"enterprise-northline-v1",
 "description":"Fictional Toronto-based payments and fintech company (venture-backed in its fictional history) with remote groups in Montreal and New York. Synthetic demo data.",
 "offices":{"Toronto":-5,"Montreal":-5,"New York":-5},
 "departments":nl_depts,
 "functions":{
  "Executive":FN("high",0.2,{"document-drafting":0.4,"research-analysis":0.3,"chat-assistant":0.3}),
  "Backend Engineering":FN("very_high",0.6,{"code-generation":0.4,"code-review":0.3,"debugging":0.2,"reconciliation":0.1}),
  "Frontend Engineering":FN("high",0.5,{"code-generation":0.5,"code-review":0.3,"debugging":0.2}),
  "Infrastructure":FN("high",0.4,{"code-generation":0.3,"debugging":0.4,"code-review":0.3}),
  "Developer Tooling":FN("very_high",0.7,{"code-generation":0.4,"code-review":0.4,"debugging":0.2}),
  "Data Engineering":FN("very_high",0.6,{"data-analysis":0.5,"code-generation":0.3,"reconciliation":0.2}),
  "Fraud Research":FN("very_high",0.8,{"fraud-analysis":0.6,"research-analysis":0.2,"data-analysis":0.2}),
  "Risk Analytics":FN("high",0.7,{"fraud-analysis":0.4,"data-analysis":0.6}),
  "Security":FN("selective",0.1,{"code-review":0.5,"chat-assistant":0.5}),
  "Compliance":FN("selective",0.3,{"compliance-review":0.7,"document-drafting":0.3}),
  "Product Management":FN("moderate",0.5,{"document-drafting":0.5,"research-analysis":0.2,"data-analysis":0.3}),
  "Design":FN("moderate",0.4,{"document-drafting":0.5,"chat-assistant":0.5}),
  "Finance":FN("selective",0.2,{"data-analysis":0.5,"reconciliation":0.3,"document-drafting":0.2}),
  "Business Operations":FN("moderate",0.2,{"data-analysis":0.4,"document-drafting":0.4,"chat-assistant":0.2}),
  "Customer Success":FN("moderate",0.2,{"customer-support":0.8,"chat-assistant":0.2}),
  "Sales & Partnerships":FN("moderate",0.1,{"document-drafting":0.5,"chat-assistant":0.5}),
  "People Operations":FN("low",0.0,{"hr-assistant":0.7,"document-drafting":0.3})},
 "projects":[
  {"key":"real-time-payments","name":"Real-Time Payments Platform","lead":"team:payments-core","start_month":0,"teams":{"payments-core":0.8,"ledger-services":0.4,"sre":0.4,"product-managers":0.3}},
  {"key":"fraud-detection-engine","name":"Fraud Detection Engine","lead":"member:fraud-research:0","start_month":0,"teams":{"fraud-research":0.9,"risk-analytics":0.6,"data-engineering":0.4,"payments-core":0.2}},
  {"key":"merchant-risk","name":"Merchant Risk Intelligence","lead":"team:risk-analytics","start_month":3,"teams":{"risk-analytics":0.7,"fraud-research":0.3,"onboarding":0.3,"data-engineering":0.2}},
  {"key":"onboarding-automation","name":"Customer Onboarding Automation","lead":"team:onboarding","start_month":2,"teams":{"onboarding":0.8,"web":0.4,"regulatory-compliance":0.4,"merchant-support":0.2}},
  {"key":"reconciliation-platform","name":"Financial Reconciliation Platform","lead":"team:ledger-services","start_month":1,"teams":{"ledger-services":0.8,"finance-team":0.5,"data-engineering":0.3}},
  {"key":"developer-platform","name":"Internal Developer Platform","lead":"team:developer-platform","start_month":0,"teams":{"developer-platform":0.9,"sre":0.5,"web":0.3,"mobile":0.3}},
  {"key":"compliance-intelligence","name":"Compliance Document Intelligence","lead":"team:regulatory-compliance","start_month":4,"teams":{"regulatory-compliance":0.8,"security-engineering":0.3,"product-managers":0.2}}],
 "personas":{"leadership":"dept:executive","financial_operator":"dept:finance","director":"dept:payments-engineering","manager":"team:payments-core","project_lead":"member:fraud-research:0","employee":"member:payments-core:3","colleague":"member:product-design:0","risk_head":"dept:risk","compliance_lead":"team:regulatory-compliance","product_manager":"member:product-managers:2","data_engineer":"member:data-engineering:4","support":"member:merchant-support:3","mobile_engineer":"member:mobile:2"},
 "names":{"team:payments-core":"Elliot Brandt","member:fraud-research:0":"Mateo Alvarez","member:payments-core:3":"Hana Takeda","member:product-design:0":"Iris Calloway"},
 "working_groups":[["member:payments-core:3","data-engineering"]],
 "project_members":{"fraud-detection-engine":["member:payments-core:3","member:product-design:0"]},
 "agents":[
  {"key":"fraud-triage-agent","name":"Fraud Triage Agent","workflow":"fraud-analysis","owner":"member:fraud-research:0","success":0.9,"retry":0.07,"drift":[{"from_month":9,"retry":0.22}]},
  {"key":"reconciliation-agent","name":"Reconciliation Agent","workflow":"reconciliation","owner":"team:ledger-services","success":0.94,"retry":0.04,"drift":[{"from_month":10,"success":0.78}]},
  {"key":"code-review-agent","name":"Code Review Agent","workflow":"code-review","owner":"team:developer-platform","success":0.95,"retry":0.05},
  {"key":"compliance-assistant","name":"Compliance Document Assistant","workflow":"compliance-review","owner":"team:regulatory-compliance","success":0.92,"retry":0.05,"drift":[{"from_month":7,"output_multiplier":1.5}]},
  {"key":"debugging-agent","name":"Debugging Agent","workflow":"debugging","owner":"team:sre","success":0.88,"retry":0.1}],
 "activity":{"events":{"demo":36000,"smoke":3600},"weekend_factor":0.1,"months":[0.7,0.6,0.78,0.86,0.8,0.9,1.05,0.95,0.88,0.92,1.0,1.1],"frontier_drift":[1.2,0.7],"rollup_scale":1.0,"unpriced_share":0.015,"holidays":["12-24","12-25","12-26","12-31","01-01"]},
 "funding":{"budget_curve":[0.6,0.8,1.0,1.0,1.05,1.15,1.1,1.05,1.0,1.0,1.05,1.15],"reserve_buffer":0.1,"unassigned_share":0.02,"factors":{"project:fraud-detection-engine":0.75,"unit:merchant-support":2.0,"unit:regulatory-compliance":1.5}},
 "controls":{"delegation_max":"300","employee_ceiling":"120","requests":[{"by":"employee","type":"personal_allowance","amount":"180"},{"by":"employee","type":"personal_allowance","amount":"450","reject_by":"financial_operator","comment":"Above this month's plan; revisit next month"},{"by":"project_lead","type":"project_funding","project":"fraud-detection-engine","amount":"1500"},{"by":"project_lead","type":"project_funding","project":"fraud-detection-engine","amount":"400"}]}
}
mem_depts=[
 D("leadership","Founders","New York",("Chief Executive Officer & Founder","Executive"),[],"Noor Haddad"),
 D("engineering","Engineering","New York",("Chief Technology Officer & Cofounder","Engineering Leadership"),[
   T("ai-ml","AI & ML",7,"AI/ML Engineering","Machine Learning Engineer","Head of AI"),
   T("backend","Backend",5,"Backend Engineering","Backend Engineer",lead=False),
   T("full-stack","Full-Stack",5,"Full-Stack Engineering","Full-Stack Engineer",lead=False)],"Jonah Whitfield"),
 D("product-design","Product & Design","New York",None,[
   T("product","Product",2,"Product Management","Product Manager",lead=False),
   T("design","Design",2,"Design","Product Designer",lead=False)]),
 D("go-to-market","Go-to-Market","New York",None,[
   T("growth","Growth",3,"Growth Marketing","Growth Marketer",lead=False),
   T("customer-success","Customer Success",2,"Customer Success","Customer Success Lead",lead=False)]),
 D("operations","Operations","New York",None,[T("ops","Business Operations",2,"Operations","Operations Manager",lead=False)]),
]
memento={
 "slug":"memento-ai","name":"Memento AI","source":"enterprise-memento-v1",
 "description":"Fictional New York startup building AI meeting intelligence: capture, summarize and search meetings and organize follow-ups. Synthetic demo data.",
 "offices":{"New York":-5},
 "departments":mem_depts,
 "functions":{
  "Executive":FN("high",0.4,{"document-drafting":0.35,"research-analysis":0.25,"meeting-summarization":0.25,"action-extraction":0.15}),
  "Engineering Leadership":FN("very_high",0.6,{"code-review":0.4,"research-analysis":0.3,"model-evaluation":0.3}),
  "AI/ML Engineering":FN("very_high",0.85,{"model-evaluation":0.35,"meeting-summarization":0.2,"transcript-analysis":0.2,"research-analysis":0.15,"code-generation":0.1}),
  "Backend Engineering":FN("very_high",0.7,{"code-generation":0.4,"code-review":0.3,"meeting-summarization":0.15,"action-extraction":0.15}),
  "Full-Stack Engineering":FN("very_high",0.7,{"code-generation":0.5,"code-review":0.3,"action-extraction":0.2}),
  "Product Management":FN("high",0.6,{"document-drafting":0.3,"meeting-summarization":0.3,"research-analysis":0.2,"action-extraction":0.2}),
  "Design":FN("high",0.5,{"document-drafting":0.5,"chat-assistant":0.5}),
  "Growth Marketing":FN("high",0.2,{"marketing-content":0.7,"research-analysis":0.3}),
  "Customer Success":FN("high",0.3,{"customer-support":0.5,"meeting-summarization":0.3,"action-extraction":0.2}),
  "Operations":FN("moderate",0.1,{"document-drafting":0.5,"data-analysis":0.5})},
 "projects":[
  {"key":"real-time-meeting-intelligence","name":"Real-Time Meeting Intelligence","lead":"dept:engineering","start_month":0,"teams":{"ai-ml":1.0,"backend":0.7,"full-stack":0.7,"product":1.0,"design":1.0}},
  {"key":"summarization-engine","name":"Transcription & Summarization Engine","lead":"member:ai-ml:0","start_month":0,"teams":{"ai-ml":1.0,"backend":0.7}},
  {"key":"meeting-knowledge-graph","name":"Meeting Knowledge Graph","lead":"member:backend:0","start_month":3,"teams":{"backend":1.0,"ai-ml":0.5,"full-stack":0.4}},
  {"key":"follow-up-agent","name":"Automated Follow-Up Agent","lead":"member:product:0","start_month":2,"teams":{"full-stack":0.7,"ai-ml":0.5,"customer-success":1.0}},
  {"key":"workspace-integrations","name":"Workspace Integrations","lead":"member:full-stack:0","start_month":1,"teams":{"full-stack":1.0,"backend":0.4,"growth":0.5}},
  {"key":"evaluation-harness","name":"Internal Evaluation Harness","lead":"member:ai-ml:1","start_month":0,"teams":{"ai-ml":1.0}}],
 "personas":{"leadership":"dept:leadership","financial_operator":"dept:leadership","manager":"dept:engineering","project_lead":"member:ai-ml:0","employee":"member:full-stack:1","head_of_ai":"team:ai-ml","ml_engineer":"member:ai-ml:1","backend_engineer":"member:backend:0","product_manager":"member:product:0","designer":"member:design:0","growth":"member:growth:0"},
 "names":{"member:ai-ml:0":"Ines Kowalski","member:full-stack:1":"Theo Brennan","member:product:0":"Priya Natarajan","member:backend:0":"Samir Haddadi","member:full-stack:0":"Ava Lindgren","member:ai-ml:1":"Kofi Mensah"},
 "agents":[
  {"key":"meeting-summarizer","name":"Meeting Summarizer","workflow":"meeting-summarization","owner":"member:ai-ml:0","success":0.93,"retry":0.08},
  {"key":"action-item-extractor","name":"Action Item Extractor","workflow":"action-extraction","owner":"member:product:0","success":0.9,"retry":0.1},
  {"key":"transcript-analyzer","name":"Transcript Analyzer","workflow":"transcript-analysis","owner":"member:ai-ml:0","success":0.88,"retry":0.12},
  {"key":"evaluation-harness-agent","name":"Evaluation Harness Agent","workflow":"model-evaluation","owner":"member:ai-ml:1","success":0.82,"retry":0.18,"drift":[{"from_month":8,"retry":0.38,"success":0.7}]},
  {"key":"code-review-agent","name":"Code Review Agent","workflow":"code-review","owner":"dept:engineering","success":0.94,"retry":0.06}],
 "activity":{"events":{"demo":16500,"smoke":1650},"weekend_factor":0.35,"months":[0.45,0.4,0.6,0.72,0.85,1.1,1.0,1.05,0.95,1.15,1.25,1.3],"frontier_drift":[0.8,1.4],"rollup_scale":2.5,"unpriced_share":0.03,"holidays":["12-25","01-01"]},
 "funding":{"budget_curve":[0.45,0.5,0.8,0.8,1.15,1.25,1.1,1.15,1.15,1.15,1.35,1.35],"reserve_buffer":0.15,"unassigned_share":0.03,"factors":{"project:evaluation-harness":0.7}},
 "controls":{"delegation_max":None,"employee_ceiling":"400","requests":[{"by":"employee","type":"personal_allowance","amount":"550"}]}
}
def scale(depts, target, pinned={}):
    """Scales team sizes to an exact headcount; pinned teams keep sizes the scenarios depend on (a team with at
    most 12 individual contributors has no technical leads, so its members report to the team lead directly)."""
    heads=sum(1 for d in depts if d.get("head"))
    teams=[t for d in depts for t in d["teams"]]
    for t in teams:
        if t["key"] in pinned: t["size"]=pinned[t["key"]]
    free=[t for t in teams if t["key"] not in pinned]
    remaining=target-heads-sum(pinned.values()); current=sum(t["size"] for t in free)
    for t in free: t["size"]=max(1,round(t["size"]*remaining/current))
    diff=remaining-sum(t["size"] for t in free)
    for t in sorted(free,key=lambda t:(-t["size"],t["key"]))[:abs(diff)]: t["size"]+=1 if diff>0 else -1
    assert headcount(depts)==target
scale(alset_depts,1100)
scale(nl_depts,260,{"payments-core":13,"fraud-research":13})
PP={"alset": ["internal-ai-productivity", "vehicle-telemetry"], "northline-financial": ["real-time-payments", "developer-platform"], "memento-ai": ["real-time-meeting-intelligence", "workspace-integrations"]}
for c in (alset,northline,memento):
    names=[d["name"] for d in c["departments"]]+[t["name"] for d in c["departments"] for t in d["teams"]]
    assert len(names)==len(set(names)),(c["slug"],[n for n in names if names.count(n)>1])
    c["persona_projects"]=PP[c["slug"]]
    c.setdefault("working_groups",[]); c.setdefault("project_members",{})
    c["headcount"]=headcount(c["departments"])
    for f in c["functions"].values(): f["budget_usd"]=BUDGET.get(c["slug"],{}).get(f["tier"],0)
    print(c["slug"],c["headcount"],file=sys.stderr)
spec={"spec_version":1,"start":"2025-11-01","months":12,"epoch_days_before_start":31,
 "profiles":{"demo":{"scale":1.0},"smoke":{"scale":0.1}},
 "models":{"frontier":{"provider":"anthropic","model":"demo-frontier-v2"},"balanced":{"provider":"openai","model":"demo-balanced-v2"},"fast":{"provider":"google","model":"demo-fast-v2"},"unpriced":{"provider":"local","model":"demo-selfhosted-v1"}},
 "rollup_suffix":"-rollup",
 "tiers":tiers,"workflows":workflows,"companies":[alset,northline,memento],
 "first_names":"Aaron Abena Adele Aiko Alejandro Amir Ana Anders Anika Arjun Astrid Bao Beatriz Bilal Camila Carmen Chen Chidi Clara Dariusz Diego Elif Elena Emeka Esme Farah Felix Fatima Gustavo Hamza Hiro Ingrid Isaac Jae Javier Jin Joao Julia Kai Kamala Karim Kenji Lars Leila Liam Lucia Mads Maria Mei Mikael Mina Nadia Nikhil Noemi Olu Omar Oskar Paulo Rafael Rania Rosa Sana Santiago Selin Soren Sven Tariq Thandi Tomas Uma Valentina Wei Xin Yara Yusuf Zara Zeynep".split(),
 "last_names":"Abara Achterberg Adeyemi Alvarado Andersen Banerjee Bauer Bianchi Castro Chaudhry Costa Dahl Delgado Dubois Eriksen Ferreira Fischer Fujita Gallagher Garcia Gunawardena Haugen Herrera Hoffmann Ibrahim Iwasaki Jansen Kapoor Kowalczyk Laine Larsen Lim Lindahl Mahmoud Marino Mendes Morales Nakamura Nguyen Novak Ochieng Olsen Ortiz Park Petrov Quintero Rahman Reyes Rossi Saito Santos Schmidt Silva Sokolov Suzuki Tanaka Torres Ueda Valdez Vargas Wagner Watanabe Weber Yilmaz Zhang Zimmermann".split()}
with open(out,'w') as f: json.dump(spec,f,indent=1); f.write('\n')
