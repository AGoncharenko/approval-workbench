#!/usr/bin/env node
// Reference screencast: two approvers decide the same invoice side by side; the loser's page refreshes live and
// the stale rejection is refused with a conflict; the admin then sees one decision in the audit history.
// Run: node .claude/skills/screencast/examples/approval_conflict.mjs   (BASE_URL defaults to http://localhost:3000)
// It changes data: it approves the first pending Acme invoice. Re-seed or use another pending invoice to re-run.
import path from 'path';
import { fileURLToPath } from 'url';
import {
  BASE_URL, runScreencast, sleep, waitVisible, click, clickButton, clickLink, fill, selectByValue,
  signIn, signOut, scrollBottom, scrollTop,
} from '../lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.resolve(__dirname, '../../../../tmp');

const BLAIR = 'approver2@acme.example.com'; // left window
const ALEX = 'approver1@acme.example.com';  // right window
const ADMIN = 'admin@acme.example.com';     // signs in on the right at the end

let invoicePath; // set when Blair opens the invoice

// Every step's actions get (blair, alex): the left and right Chrome windows.
const STEPS = [
  {
    id: '01_intro',
    narration: 'Welcome to the invoice approval workbench. On the left is Blair, and on the right is Alex. Both are approvers at Acme Industries, and both will open the same pending invoice. One approves it, and we will see what happens when the other one tries to reject it a moment later.',
    actions: async (blair, alex) => {
      await Promise.all([blair.get(`${BASE_URL}/session/new`), alex.get(`${BASE_URL}/session/new`)]);
      await sleep(3000);
    },
  },
  {
    id: '02_sign_in',
    narration: 'Both sign in with their own accounts. Every account in this demo uses synthetic data.',
    actions: async (blair, alex) => {
      await sleep(1000);
      await signIn(blair, BLAIR);
      await signIn(alex, ALEX);
    },
  },
  {
    id: '03_pending',
    narration: 'Approvers see the submitted invoices of their own company, never drafts and never another company. Blair filters to the invoices waiting for approval and opens the first one. Alex opens the same invoice.',
    actions: async (blair, alex) => {
      await sleep(3000);
      await selectByValue(blair, 'select[name="status"]', 'pending');
      await clickButton(blair, 'Filter');
      await sleep(2000);
      await click(blair, 'table tbody tr:first-child td:first-child a');
      await waitVisible(blair, 'textarea[name="transition[reason]"]');
      invoicePath = new URL(await blair.getCurrentUrl()).pathname;
      await sleep(1000);
      await alex.get(BASE_URL + invoicePath);
      await waitVisible(alex, 'textarea[name="transition[reason]"]');
      await sleep(1000);
    },
  },
  {
    id: '04_review',
    narration: 'The detail page shows the vendor, the exact amount and currency, the due date, and the version number each of them is deciding on. Blair starts typing a reason for rejecting it.',
    actions: async (blair) => {
      await sleep(3500);
      await scrollBottom(blair);
      await sleep(800);
      await fill(blair, 'textarea[name="transition[reason]"]', 'This looks like a duplicate of an invoice we already paid.');
      await sleep(1500);
    },
  },
  {
    id: '05_alex_approves',
    narration: 'Meanwhile, Alex approves the invoice. Watch the left window: it refreshes by itself, the status changes to approved, and the reason Blair typed is kept.',
    actions: async (blair, alex) => {
      await sleep(2000);
      await scrollBottom(alex);
      await sleep(600);
      await clickButton(alex, 'Approve');
      await sleep(1500);
      await scrollTop(blair);
      await sleep(4000);
    },
  },
  {
    id: '06_stale_reject',
    narration: 'Blair now clicks Reject. The form still carries the version Blair reviewed, so the server refuses the stale decision and says exactly what changed and who changed it. Nothing is applied twice.',
    actions: async (blair) => {
      await sleep(3500);
      await clickButton(blair, 'Reject');
      await waitVisible(blair, '#notice');
      await scrollTop(blair);
      await sleep(5000);
    },
  },
  {
    id: '07_admin_audit',
    narration: 'Finally, an admin opens the audit history on the right. It records who did what and when, and it shows a single approval for this invoice. Audit entries cannot be edited or deleted, even directly in the database.',
    actions: async (blair, alex) => {
      await sleep(1500);
      await signOut(alex);
      await signIn(alex, ADMIN);
      await clickLink(alex, 'Audit history');
      await sleep(6000);
    },
  },
  {
    id: '08_outro',
    narration: 'Thank you for watching. Stale or repeated decisions never apply twice, and every decision is audited.',
    actions: async () => { await sleep(8000); },
  },
];

runScreencast({ slug: 'approval_conflict', outDir: OUT_DIR, steps: STEPS, windows: 2 })
  .catch(err => { console.error(err); process.exit(1); });
