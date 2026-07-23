# Trading-Journal-App-using-Supabase-VSCode-HTML-CSS-JS

## Overview

This project is a custom-built trading journal application I designed and built to track and analyze my forex trading performance across multiple strategies. It's a single-file HTML, CSS, and JavaScript application connected to a Supabase backend, which handles persistent, cloud-synced storage for every trade I log. The goal was to move away from generic spreadsheet journals and build something tailored exactly to how I trade — strategy-isolated data, session/pair breakdowns, and visual performance tracking in one place.

## Objectives

- Track every trade with full detail across multiple strategies (Engulfing, ZM DR/IDR, New Engulfing, Mido Main)
- Monitor performance metrics like win rate, net R:R, and account growth over time
- Identify strengths and weaknesses in execution across different pairs and trading sessions
- Keep each strategy's data isolated so results don't blend together and skew analysis
- Build a system I could keep expanding as my trading evolves

## Tools & Programs Used

- Visual Studio Code (VS Code) — the code editor used to write and edit the HTML, CSS, and JavaScript
- VS Code Live Server extension — used to run the app locally in the browser with live reload while building
- Supabase — backend-as-a-service used for the database (Postgres), REST API, and file storage (trade screenshots)
- Supabase SQL Editor — used to write and run the SQL that created the database schema

## How It Was Built

### 1. Planning the structure Before writing any code, I mapped out what the journal needed

a dashboard, a logbook, a calendar/heatmap view, monthly breakdowns, and a trade entry form — all pulling from the same underlying trade data but presented differently.

### 3. Setting up the editor

I used VS Code as my code editor. I opened the project as a folder (File → Open Folder) so I could use the Live Server extension, which lets the HTML file run in the browser and auto-refresh every time I saved a change — this made it possible to see UI changes instantly instead of manually reloading.

### 4. Writing the front end (HTML/CSS)

The entire interface is built in one HTML file. The <style> block at the top defines a design system using CSS variables (a :root { --bg: ...; --accent: ...; } block) for colors, spacing, and theming, so the whole app's look is controlled from one place instead of repeating values everywhere. The HTML body defines the sidebar navigation, the dashboard panels, the logbook table, and the trade entry modal — all as one page, with JavaScript controlling which section is visible at any time.

### 7. Building the database in Supabase

I created a free Supabase project, then used the SQL Editor inside the Supabase dashboard to write CREATE TABLE statements defining the schema — tables for trades and summaries, with columns for pair, session, strategy, entry/exit details, R:R outcome, and notes. Supabase automatically turns these tables into a REST API, and generates a project URL and an API (anon) key used to authenticate requests from the app.

### 8. Connecting the front end to Supabase In the JavaScript

I wrote small helper functions that build the request URL (project URL + table name), attach the required headers (apikey, Authorization: Bearer <key>, Content-Type), and use fetch() to send GET/POST/PATCH/DELETE requests. Every part of the app that needs data — the dashboard, the logbook, the calendar — goes through these same helper functions rather than writing a new fetch call each time.

### 9. Writing the JavaScript logic

The JavaScript is plain (vanilla) JS — no frameworks or build tools. It's organized into a few clear categories of functions:

- Rendering functions (renderDash(), renderSummaryEditor(), renderContextTagOptions()) — pull trade data and rebuild the relevant part of the page

- Interaction handlers (setDirection(), toggleStrategyPanel(), selectStrategy(), dashSetMode(), dashNav()) — respond to clicks/toggles, update state, then call the render functions again to reflect the change
  
- Date/formatting utilities (dayAbbr(), fmtDate(), weekOfMonth(), isValidTradeDate()) — keep date handling and display consistent across every view instead of repeating logic
  
- Modal/form logic (openTradeModal(tid)) — opens the trade entry form, pre-filling it with existing data if editing a trade, or opening blank for a new one; also handles attaching trade screenshots and chart links
  
- Navigation (goPage(id)) — swaps between the Dashboard, Logbook, Calendar, and other views by toggling which container is visible, acting as a lightweight single-page app without a router library

### 8. Version control

AI assistance (Claude) was used to help design the architecture, write and debug the JavaScript, and refine the UI — while I fully directed the feature set, data structure, and design decisions based on my own trading workflow.

## Screenshots

### App Previews:

Dashboard

<img width="1633" height="977" alt="image" src="https://github.com/user-attachments/assets/64b926f3-810e-4bab-bd0f-fbd7dca5e7fe" />


Logbook

<img width="1639" height="963" alt="image" src="https://github.com/user-attachments/assets/5b2dc7f1-61a0-40d1-a73f-84ce63f60f59" />


Calendar / Heatmap View

<img width="1620" height="714" alt="image" src="https://github.com/user-attachments/assets/86827775-6300-4cfe-93fb-ab986359b2dc" />


Live Stats View

<img width="1637" height="975" alt="image" src="https://github.com/user-attachments/assets/d0ce8faf-e20d-46f0-9cce-3087dda5bb33" />

### Code Previews:

Editor / File Structure

<img width="1710" height="1073" alt="image" src="https://github.com/user-attachments/assets/5454b958-6114-46d9-a7d1-dd0f8978e6d3" />

Supabase SQL Editor

<img width="1628" height="908" alt="image" src="https://github.com/user-attachments/assets/f5d05f5a-fd91-4b83-b539-e570439e140b" />

## Example: JavaScript Rendering Function

Since not every part of the logic has a matching screenshot, here's a real example of one of the core rendering functions used to build the dashboard view:

function dashSetMode(mode){
  // Updates the active dashboard mode (e.g. Live / Backtest / All)
  
  // and re-renders the dashboard and heatmap to reflect the change
  
  syncDashButtons();
  renderDash();
  renderDashHeatmap();
}

## Example: Supabase Request Helper

// Builds the request to Supabase's REST API using the project URL and anon key

const url = 'https://<project-ref>.supabase.co/rest/v1/' + path;
const headers = {
  'Content-Type': 'application/json',
  'apikey': AKEY,
  'Authorization': 'Bearer ' + AKEY,
  'Prefer': 'return=representation'
};

(Actual project URL and API key have been removed from this example for security.)

## Key Analysis

The journal is built to answer questions like: How is each strategy performing individually? What's my win rate and net R:R by month, week, and session? How consistent is my execution across different pairs? Where are the patterns in my wins vs. losses?

## Data Structure

Trades are logged with full context — pair, session, strategy, entry/exit details, R:R outcome, and notes — with support for both live and backtested trades, kept strategy-isolated so results don't blend across different systems. The schema was defined directly in Supabase's SQL Editor before any front-end work connected to it.

## Key Features

- Dashboard with equity curve, win rate, and net R:R at a glance
- Logbook for detailed trade-by-trade entries with screenshots
- Calendar/heatmap view to spot performance patterns by day
- Monthly & weekly breakdowns with editable summaries
- Live stats view separate from backtesting data
- Multi-strategy support (Engulfing, ZM DR/IDR, New Engulfing, Mido Main)
  
## Data

Trade data is stored in Supabase, covering entry/exit details, strategy tags, sessions, pairs, R:R outcomes, and trade screenshots. Credentials are not included in this repo.

## Skills Demonstrated

This project demonstrates my ability to: design and build a functional full-stack tool from scratch, write and structure real JavaScript logic rather than relying on templates, design a database schema and connect it to a live front end, and build a system tailored to my own workflow rather than using off-the-shelf tools.

## Future Improvements

Potential improvements to this project include:

- Adding deeper statistical breakdowns (e.g. performance by day of week)
- Building automated reporting/export features
- Introducing authentication for secure multi-device access
- Expanding analysis to compare strategies head-to-head over time
