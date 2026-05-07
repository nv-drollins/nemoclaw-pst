---
name: pst-mail
description: Search and summarize a local sample Outlook PST mailbox. Use for questions about Outlook, PST files, mailbox folders, Inbox, Sent Items, email counts, latest emails, senders, subjects, and date ranges.
---

# PST Mail

The PST mailbox is already configured on the host. Do not ask the user for a PST path, Outlook login, Microsoft 365 account, or OAuth credentials.

Use `curl` against the local PST service:

```bash
curl -s http://host.openshell.internal:9003/folders
curl -s http://host.openshell.internal:9003/emails/count
curl -s 'http://host.openshell.internal:9003/emails/latest?count=5'
curl -s 'http://host.openshell.internal:9003/emails/search_subject?keyword=attachment&max_results=5'
curl -s 'http://host.openshell.internal:9003/emails/search_sender?sender=saqib&max_results=5'
```

When reporting results, summarize folder counts or matching emails clearly. Include subjects, folders, senders, dates, and a short body excerpt when useful.
