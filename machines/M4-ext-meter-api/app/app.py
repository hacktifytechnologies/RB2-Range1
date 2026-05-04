import os
import logging
from flask import Flask, request, jsonify, Response
from lxml import etree
from functools import wraps

app = Flask(__name__)

LOG_DIR = "/var/log/bunl/meter-api"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/access.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

VALID_API_KEYS = {"soap-9f3b2d1e7a8c4f6d"}

def require_api_key(f):
    @wraps(f)
    def dec(*a, **kw):
        key = request.headers.get("X-API-KEY", "")
        if key not in VALID_API_KEYS:
            logging.warning(f"INVALID_KEY|ip={request.remote_addr}|key={key[:12]}")
            return Response(
                '<?xml version="1.0"?><error><code>401</code><message>Invalid or missing X-API-KEY header.</message></error>',
                status=401, mimetype="application/xml"
            )
        return f(*a, **kw)
    return dec

def parse_meter_xml(xml_data):
    # Vulnerable: resolve_entities not disabled, no defenses
    parser = etree.XMLParser(resolve_entities=True, no_network=False, load_dtd=True)
    try:
        root = etree.fromstring(xml_data.encode() if isinstance(xml_data, str) else xml_data, parser)
        return root, None
    except etree.XMLSyntaxError as e:
        return None, str(e)

@app.route("/api/meter/submit", methods=["POST"])
@require_api_key
def submit_meter_reading():
    ip = request.remote_addr
    content_type = request.content_type or ""
    if "xml" not in content_type and "text/plain" not in content_type:
        return Response(
            '<?xml version="1.0"?><error><code>415</code><message>Content-Type must be application/xml or text/xml</message></error>',
            status=415, mimetype="application/xml"
        )
    xml_data = request.get_data()
    logging.info(f"METER_SUBMIT|ip={ip}|size={len(xml_data)}")
    root, err = parse_meter_xml(xml_data)
    if err:
        logging.warning(f"XML_PARSE_ERROR|ip={ip}|error={err}")
        return Response(
            f'<?xml version="1.0"?><error><code>400</code><message>XML parse error: {err}</message></error>',
            status=400, mimetype="application/xml"
        )
    meter_id = ""
    reading = ""
    for child in root:
        if child.tag == "MeterId":
            meter_id = child.text or ""
        elif child.tag == "ReadingValue":
            reading = child.text or ""
    logging.info(f"METER_PARSED|ip={ip}|meter_id={meter_id[:80]}|reading={reading[:20]}")
    resp_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<MeterDataResponse>
  <Status>ACCEPTED</Status>
  <AcknowledgementId>ACK-{abs(hash(meter_id + reading)) % 9999999:07d}</AcknowledgementId>
  <MeterId>{meter_id}</MeterId>
  <ReadingValue>{reading}</ReadingValue>
  <ReceivedAt>2025-11-15T09:00:00+05:30</ReceivedAt>
  <ProcessingNode>mdr-node-01.bunl-internal.net</ProcessingNode>
</MeterDataResponse>"""
    return Response(resp_xml, status=200, mimetype="application/xml")

@app.route("/api/meter/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "BUNL Meter Data Exchange API", "version": "2.0.1"})

@app.route("/api/meter/schema", methods=["GET"])
@require_api_key
def schema():
    return Response("""<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="MeterDataSubmission">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="MeterId" type="xs:string"/>
        <xs:element name="ReadingValue" type="xs:decimal"/>
        <xs:element name="ReadingDate" type="xs:date" minOccurs="0"/>
        <xs:element name="MeterType" type="xs:string" minOccurs="0"/>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>""", mimetype="application/xml")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)
