import os, sys
sys.argv = ["x"]
os.environ.setdefault("VERSION", "1.5")
import importlib.util
spec = importlib.util.spec_from_file_location("asc", os.path.join(os.path.dirname(__file__), "asc_whats_new.py"))
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
call = asc.call
bundle = os.environ.get("APP_BUNDLE_ID") or "com.baturinigor.zenhab"
app_id = call("GET", "/apps", params={"filter[bundleId]": bundle})["data"][0]["id"]
for g in call("GET", f"/apps/{app_id}/subscriptionGroups")["data"]:
    print("GROUP", g["attributes"].get("referenceName"))
    for s in call("GET", f"/subscriptionGroups/{g['id']}/subscriptions")["data"]:
        a = s["attributes"]
        print(" SUB", a.get("productId"), a.get("subscriptionPeriod"), a.get("state"))
        offers = call("GET", f"/subscriptions/{s['id']}/introductoryOffers", params={"limit": 200, "include": "territory"})
        modes = {}
        for o in offers["data"]:
            oa = o["attributes"]
            k = (oa.get("offerMode"), oa.get("duration"), oa.get("numberOfPeriods"), oa.get("startDate"), oa.get("endDate"))
            modes[k] = modes.get(k, 0) + 1
        print("   intro offers:", len(offers["data"]), "territories" if offers["data"] else "none")
        for k, n in modes.items():
            print("   ", k, "x", n)
for v in call("GET", f"/apps/{app_id}/appStoreVersions", params={"limit": 3})["data"]:
    print("VERSION", v["attributes"]["versionString"], v["attributes"].get("appStoreState"))
