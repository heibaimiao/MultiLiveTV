# Minimal TVBox `base.spider.Spider` stub so EHR663 py scripts can run locally.
import re

import requests


class Spider:
    def fetch(
        self,
        url,
        params=None,
        cookies=None,
        headers=None,
        timeout=20,
        verify=True,
        stream=False,
        allow_redirects=True,
    ):
        rsp = requests.get(
            url,
            params=params,
            cookies=cookies,
            headers=headers,
            timeout=timeout,
            verify=verify,
            stream=stream,
            allow_redirects=allow_redirects,
        )
        rsp.encoding = "utf-8"
        return rsp

    def post(
        self,
        url,
        params=None,
        data=None,
        json=None,
        cookies=None,
        headers=None,
        timeout=20,
        verify=True,
        stream=False,
        allow_redirects=True,
    ):
        rsp = requests.post(
            url,
            params=params,
            data=data,
            json=json,
            cookies=cookies,
            headers=headers,
            timeout=timeout,
            verify=verify,
            stream=stream,
            allow_redirects=allow_redirects,
        )
        rsp.encoding = "utf-8"
        return rsp

    def cleanText(self, src):
        if not src:
            return ""
        return re.sub(
            "[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF\U0001F1E0-\U0001F1FF]",
            "",
            src,
        )

    def log(self, msg):
        print(msg)
