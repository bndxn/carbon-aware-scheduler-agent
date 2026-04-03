import requests

headers = {"Accept": "application/json"}

r = requests.get(
    "https://api.carbonintensity.org.uk/regional/postcode/{postcode}",
    params={},
    headers=headers,
)

print(r.json())
