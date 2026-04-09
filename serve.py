import http.server
import os

os.chdir("/Users/miskomini/Downloads/Pokladňa - claude")
handler = http.server.SimpleHTTPRequestHandler
httpd = http.server.HTTPServer(("", 8080), handler)
print("Serving at http://localhost:8080")
httpd.serve_forever()
