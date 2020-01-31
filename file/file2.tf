# variable "vpc_endpoint"    {
#     //default = "vpc-es-development-2mk5h5sefn64r6j3wbazcjfoui.eu-central-1.es.amazonaws.com"
# }

# variable "retention_period_in_days" {
#   //default = "7"
# }

resource "local_file" "IndexDeletionCurtator" {
  content  = <<EOF

#!/usr/bin/python
# -*- coding: utf-8 -*-
"""
This AWS Lambda function allowed to delete the old Elasticsearch index
"""
import re
import os
import json
import time
import datetime
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import create_credential_resolver
from botocore.httpsession import URLLib3Session
from botocore.session import get_session
import sys

if sys.version_info[0] == 3:
    from urllib.request import quote
else:
    from urllib import quote


class ES_Exception(Exception):
    """Exception capturing status_code from Client Request"""
    status_code = 0
    payload = ""

    def __init__(self, status_code, payload):
        self.status_code = status_code
        self.payload = payload
        Exception.__init__(self,
                           "ES_Exception: status_code={}, payload={}".format(
                               status_code, payload))


class ES_Cleanup(object):

    name = "lambda_es_cleanup"

    def __init__(self, event, context):
        """Main Class init
        Args:
            event (dict): AWS Cloudwatch Scheduled Event
            context (object): AWS running context
        """
        self.report = []
        self.event = event
        self.context = context

        self.cfg = {}
        #self.cfg["es_endpoint"] = "vpc-tsi-4ob64gbjtaarddqn4b2cdcqwd4.eu-central-1.es.amazonaws.com"
        self.cfg["es_endpoint"] = os.environ['vpc_endpoint']
        self.cfg["index"] = ".*\d{4}.\d{2}.\d{2}"
        self.cfg["skip_index"] = ".kibana*"
        self.cfg["delete_after"] = os.environ['retention_period_in_days']
        self.cfg["es_max_retry"] = "3"
        self.cfg["index_format"] = "%Y.%m.%d"

        if not self.cfg["es_endpoint"]:
            raise Exception("[es_endpoint] OS variable is not set")

    def get_parameter(self, key_param, default_param=None):
        """helper function to retrieve specific configuration
        Args:
            key_param     (str): key_param to read from "event" or "environment" variable
            default_param (str): default value
        Returns:
            string: parameter value or None
        """
        return self.event.get(key_param, os.environ.get(key_param, default_param))

    def send_to_es(self, path, method="GET", payload={}):
        """Low-level POST data to Amazon Elasticsearch Service generating a Sigv4 signed request
        Args:
            path (str): path to send to ES
            method (str, optional): HTTP method default:GET
            payload (dict, optional): additional payload used during POST or PUT
        Returns:
            dict: json answer converted in dict
        Raises:
            #: Error during ES communication
            ES_Exception: Description
        """
        if not path.startswith("/"):
            path = "/" + path

        es_region = self.cfg["es_endpoint"].split(".")[1]

        headers = {
                "Host": self.cfg["es_endpoint"],
                "Content-Type": "application/json"
            }

        # send to ES with exponential backoff
        retries = 0
        while retries < int(self.cfg["es_max_retry"]):
            if retries > 0:
                seconds = (2**retries) * .1
                time.sleep(seconds)

            req = AWSRequest(
                method=method,
                url="https://{}{}".format(
                    self.cfg["es_endpoint"], quote(path)),
                data=json.dumps(payload),
                params={"format": "json"},
                headers=headers)
            credential_resolver = create_credential_resolver(get_session())
            credentials = credential_resolver.load_credentials()
            SigV4Auth(credentials, 'es', es_region).add_auth(req)

            try:
                preq = req.prepare()
                session = URLLib3Session()
                res = session.send(preq)
                if res.status_code >= 200 and res.status_code <= 299:
                    return json.loads(res.content)
                else:
                    raise ES_Exception(res.status_code, res._content)

            except ES_Exception as e:
                if (e.status_code >= 500) and (e.status_code <= 599):
                    retries += 1  # Candidate for retry
                else:
                    raise  # Stop retrying, re-raise exception

    def delete_index(self, index_name):
        """ES DELETE specific index
        Args:
            index_name (str): Index name
        Returns:
            dict: ES answer
        """
        return self.send_to_es(index_name, "DELETE")

    def get_indices(self):
        """ES Get indices
        Returns:
            dict: ES answer
        """
        return self.send_to_es("/_cat/indices")


def lambda_handler(event, context):
    """Main Lambda function
    Args:
        event (dict): AWS Cloudwatch Scheduled Event
        context (object): AWS running context
    Returns:
        None
    """
    es = ES_Cleanup(event, context)
    # Index cutoff definition, remove older than this date
    # print(es.cfg["index"])
    # print(es.cfg["delete_after"])
    earliest_to_keep = datetime.date.today() - datetime.timedelta(
        days=int(es.cfg["delete_after"]))
    for index in es.get_indices():
        print("Found index: {}".format(index["index"]))
        if re.search(es.cfg["skip_index"], index["index"]):
            # ignore .kibana index
            continue

        idx_split = index["index"].rsplit("-",
            1 + es.cfg["index_format"].count("-"))
        idx_name = idx_split[0]
        idx_date = '-'.join(word for word in idx_split[1:])

        if re.search(es.cfg["index"], index["index"]):

            if idx_date <= earliest_to_keep.strftime(es.cfg["index_format"]):
                print("Deleting index: {}".format(index["index"]))
                es.delete_index(index["index"])
            else:
                print("Keeping index: {}".format(index["index"]))
        else:
            print("Index '{}' name '{}' did not match pattern '{}'".format(index["index"], idx_name, es.cfg["index"]))
EOF
  filename = "./package/es-cleanup.py"

}

data "archive_file" "IndexDeletionCurtator-archive" {
  type        = "zip"
  output_path = "./package/index.zip"
  source_dir  = "./package"

  depends_on = [
    "local_file.IndexDeletionCurtator",
  ]
}