# Trading-Journal-App-using-Supabase-HTML-CSS-JS

## 📌 Overview

This project is a custom-built trading journal application designed to track and analyze my forex trading performance across multiple strategies. It's a single-file HTML/CSS/JS app connected to a Supabase backend for persistent, cloud-synced storage, allowing me to log trades, review performance, and refine my strategy execution over time.

## 🎯 Objectives

Track every trade with full detail across multiple strategies, monitor performance metrics like win rate, R:R, and growth over time, identify strengths and weaknesses in execution across different pairs and sessions, build a system that isolates data per strategy for cleaner analysis, and create a foundation I can keep expanding as my trading evolves.

## 🛠️ Tools & Skills

HTML/CSS/JavaScript · Supabase (backend & storage) · UI/UX Design · Data Visualization · Front-End Development · Trading Strategy Analysis

## 🧩 How It Was Built

Built as a single-file HTML, CSS, and JavaScript application — no frameworks — with a Supabase backend handling data storage, API calls, and image storage for trade screenshots. I used the Supabase SQL Editor to design and set up the database schema directly — creating the tables for trades and summaries, defining column types, and running the setup scripts that structure how trade data is stored. I used AI-assisted development (working with Claude) to help design the architecture, write and debug the JavaScript logic, and refine the UI, while I directed the feature set, data structure, and design decisions based on my own trading workflow.

## 🖼️ Screenshots
App Preview

Dashboard

<!-- paste dashboard screenshot here -->

Logbook

<!-- paste logbook screenshot here -->

Calendar / Heatmap View

<!-- paste calendar/heatmap screenshot here -->

Monthly Breakdown

<!-- paste monthly breakdown screenshot here -->

Trade Entry Modal

<!-- paste trade modal screenshot here -->

Live Stats View

<!-- paste live stats screenshot here -->
Code Preview

Editor / File Structure

<!-- paste code editor screenshot here -->

Design System (CSS Variables)

<!-- paste CSS variables screenshot here -->

Live Run / Connected to Supabase

<!-- paste terminal or dev tools screenshot here -->

Supabase SQL Editor

<!-- paste SQL editor screenshot here -->
## 📊 Key Analysis

The journal is built to answer questions like: How is each strategy performing individually? What's my win rate and net R:R by month, week, and session? How consistent is my execution across different pairs? Where are the patterns in my wins vs. losses?

## 📊 Data Structure

Trades are logged with full context — pair, session, strategy, entry/exit details, R:R outcome, and notes — with support for both live and backtested trades, kept strategy-isolated so results don't blend across different systems.

## 💡 Key Features
Dashboard with equity curve, win rate, and net R:R at a glance
Logbook for detailed trade-by-trade entries with screenshots
Calendar/heatmap view to spot performance patterns by day
Monthly & weekly breakdowns with editable summaries
Live stats view separate from backtesting data
Multi-strategy support (Engulfing, ZM DR/IDR, New Engulfing, Mido Main)

## 📂 Data

Trade data is stored in Supabase, covering entry/exit details, strategy tags, sessions, pairs, R:R outcomes, and trade screenshots. Credentials are not included in this repo.

## 🚀 Skills Demonstrated

This project demonstrates my ability to: design and build a functional full-stack tool from scratch, structure and manage real data through a live database, translate raw trade data into clear performance metrics, and build a system tailored to my own workflow rather than relying on off-the-shelf tools.

## 🚀 Future Improvements

Potential improvements to this project include:

Adding deeper statistical breakdowns (e.g. performance by session, by day of week)
Building automated reporting/export features
Introducing authentication for secure multi-device access
Expanding analysis to compare strategies head-to-head over time
