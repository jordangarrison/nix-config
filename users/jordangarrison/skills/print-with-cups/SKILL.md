---
name: print-with-cups
description: Diagnose and operate Linux CUPS printers safely. Use for printer or queue readiness checks, CUPS troubleshooting, printing whole PDFs or selected PDF page ranges, duplex long-edge printing, confirming that a printer picked up a submitted job, and correcting a mistaken print by canceling only the unfinished job before resubmitting.
---

# Print with CUPS

Use CUPS command-line tools to discover destinations, validate each request, submit the smallest intended job, and track its exact request ID.

## Safety rules

- Treat `lp`, `cancel`, `cupsenable`, and `cupsaccept` as state-changing commands.
- Run read-only discovery and diagnosis freely. Submit only when the user asked to print or approved a clearly stated print plan.
- Before submission, state destination, PDF, page range or whole document, copy count, and simplex or duplex mode. Ask only for missing choices that could change physical output.
- Use one copy unless the user explicitly requests more.
- Quote file paths and use `--` before the PDF path in `lp`.
- Apply settings per job. Do not change persistent defaults with `lpoptions -o`, `lpadmin`, or similar commands unless explicitly requested.
- Never hard-code a destination discovered on another machine or in an earlier session.
- Never use `cancel -a`. Cancel only an exact, verified unfinished request ID.
- Do not enable a disabled queue blindly: enabling it can release older waiting jobs. Inspect pending jobs and get approval first.

## 1. Check tools and discover destinations

Check for required commands:

```bash
command -v lp lpstat lpoptions cancel
```

If unavailable, install the platform's CUPS client tools. On Nix systems, use `nix shell nixpkgs#cups` or run an individual check such as `nix shell nixpkgs#cups -c lpstat -r`.

Inspect current CUPS state:

```bash
lpstat -r
lpstat -e
lpstat -p -d
lpstat -a
lpstat -v
lpstat -W not-completed -o
```

Select a destination in this order:

1. Use a destination explicitly named by the user, after verifying it exists.
2. Otherwise use the configured default if it is enabled and accepting jobs.
3. Otherwise use the only enabled, accepting destination if exactly one exists.
4. If multiple viable destinations remain, show their discovered names and statuses and ask the user to choose.

Assign the exact chosen name from current discovery output to the `printer` shell variable for later commands.

## 2. Diagnose readiness

Inspect the selected destination and its queue:

```bash
lpstat -l -p "$printer"
lpstat -a "$printer"
lpstat -v "$printer"
lpstat -W not-completed -o "$printer"
```

Require all of these before submission:

- CUPS scheduler is running.
- Destination exists, is enabled, and is accepting jobs.
- Status has no unresolved media, door, connection, authentication, filter, or backend error.
- Existing jobs and their effect on ordering are understood.

Treat `idle` as ready and `now printing` as busy but operational. Treat disabled, rejecting, stopped, held, or faulted states as not ready. If the scheduler is unavailable, inspect the local service where applicable, for example:

```bash
systemctl status cups --no-pager
```

Report the failing layer before proposing a change. Do not start services, alter configuration, enable queues, or release held jobs unless the user authorizes that remediation.

## 3. Validate the PDF and requested pages

Resolve the intended PDF to an absolute path, then confirm it is readable and actually a PDF:

```bash
test -r "$pdf"
file --brief --mime-type -- "$pdf"
pdfinfo "$pdf"
```

Use `pdfinfo` to check total pages. Accept page selections such as `4`, `4-9`, or `1-3,8,11-14`; reject zero, reversed ranges, malformed values, and pages beyond the document.

Interpret page numbers as the PDF's one-based page sequence, which may differ from page labels printed inside the document. Clarify when that distinction matters.

If `pdfinfo` is unavailable, install Poppler's CLI tools (for example, `nix shell nixpkgs#poppler-utils` on Nix) or use another trustworthy page-count check. Do not submit an unvalidated range.

## 4. Check duplex capability

Inspect advertised per-job options:

```bash
lpoptions -p "$printer" -l
```

Prefer the standard IPP option:

```text
sides=two-sided-long-edge
```

If the queue exposes only a legacy `Duplex` option, use the exact advertised long-edge value, commonly `DuplexNoTumble`. Do not guess a vendor-specific value. If no long-edge capability is advertised, stop and report that instead of silently printing one-sided.

For a legacy queue that explicitly advertises `DuplexNoTumble`, replace the standard sides option in submission commands with `-o Duplex=DuplexNoTumble`.

## 5. Submit the job

Use `-d` for the discovered destination and preserve `lp` output because it contains the request ID.

Print the whole PDF:

```bash
lp -d "$printer" -n 1 -- "$pdf"
```

Print selected pages:

```bash
lp -d "$printer" -n 1 -o page-ranges="$pages" -- "$pdf"
```

Print the whole PDF duplex on the long edge:

```bash
lp -d "$printer" -n 1 -o sides=two-sided-long-edge -- "$pdf"
```

Print selected pages duplex on the long edge:

```bash
lp -d "$printer" -n 1 -o page-ranges="$pages" -o sides=two-sided-long-edge -- "$pdf"
```

Add more copies with `-n` only when explicitly requested. Record the exact request ID returned by `lp`, normally shaped like `destination-number`.

## 6. Verify pickup

Distinguish these states:

- **Accepted:** `lp` returned a request ID.
- **Queued:** the exact request appears in the not-completed list.
- **Picked up:** destination status shows the request is processing, or it transitions from pending to processing.
- **Scheduler-finished:** the request leaves the active queue after observed processing and appears in completed history without a reported fault.
- **Physically complete:** the user or printer confirms sheets finished; CUPS alone may only prove data reached the device.

Check immediately after submission and again after a short interval:

```bash
lpstat -W not-completed -o "$printer"
lpstat -l -p "$printer"
lpstat -W completed -o "$printer"
```

Match the exact request ID. Do not call a job picked up merely because submission succeeded. A request appearing only in terminal history might also have been canceled or aborted. If completed-job history is unavailable or the job finishes too quickly to observe processing, state the evidence and its limit rather than claiming pickup or physical completion.

## 7. Correct a mistaken job

First list unfinished work and identify the exact request by destination, ID, owner, and document:

```bash
lpstat -l -W not-completed -o "$printer"
```

Before cancellation or resubmission, warn:

> Canceling stops only the unfinished portion. Sheets already printed cannot be recalled, and resubmitting overlapping pages can produce duplicates.

Then:

1. Cancel only the verified request:

   ```bash
   cancel "$job_id"
   ```

2. Confirm the request no longer appears in the unfinished queue.
3. If the physical printer continues, use its control panel to stop the buffered job and wait for output to settle.
4. Ask which pages or sheets physically printed; never infer that solely from CUPS state.
5. Confirm corrected destination, pages, copies, and duplex mode.
6. Decide explicitly between reprinting the full corrected selection or only a known remaining range. For duplex jobs, account for two PDF pages per completed sheet and an uncertain partially printed sheet.
7. Submit the corrected job and track its new request ID separately.

Report both canceled and replacement request IDs, plus any risk of duplicate or partial output.
