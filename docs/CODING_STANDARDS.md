# One Gun - Coding Standards

Version: 1.0

This document defines the development standards for One Gun.

The goal is to keep the project clean, scalable, easy to maintain, and easy for both humans and AI to work on.

These standards should be followed for every implementation unless explicitly instructed otherwise.

---

# Project Philosophy

One Gun is a long-term project.

Every feature should be implemented as if it will be expanded later.

Never implement a feature as a one-off solution if a reusable system can reasonably be created.

Prioritize:

- Readability
- Maintainability
- Extensibility
- Simplicity

Avoid clever code that is difficult to understand.

Future readability is more important than saving a few lines of code.

---

# Claude's Responsibilities

Before writing any code:

1. Understand the requested feature.
2. Identify the systems involved.
3. Explain the implementation plan.
4. List every file that will be modified.
5. Wait for approval if the requested changes are larger than expected.

Never immediately begin modifying files without first understanding the request.

---

# Scope Control

Only modify files directly related to the requested feature.

Do NOT:

- Rewrite unrelated systems
- Refactor unrelated code
- Rename files without permission
- Move folders without permission
- Change gameplay values unless requested

Stay focused on the requested task.

---

# Architecture Philosophy

Each script should have one clear responsibility.

Examples:

RoundManager
- Round flow
- Match flow

WeaponManager
- Weapon spawning
- Weapon ownership

HUDManager
- HUD only

VictoryPresentation
- Victory scene
- Podium
- Winner presentation

PowerupManager
- Powerups only

Avoid giant scripts that manage multiple unrelated systems.

---

# Reuse Existing Systems

Before creating:

- new scripts
- new managers
- new resources

Always check whether an existing system should be expanded instead.

Avoid duplicate functionality.

---

# Modular Design

Whenever practical:

Design systems to be reusable.

Example:

Don't hardcode:

VictoryPodium

Instead create:

PodiumScene

which can later support:

- Victory
- MVP
- Tournament
- Seasonal Events

---

# Data Driven Design

Whenever possible:

Gameplay values should come from:

Resources (.tres)

Configuration files

Lobby settings

Avoid hardcoding gameplay values inside scripts.

Examples:

Good

Reload Time

Weapon Stats

Powerup Duration

Knockback

Stamina Cost

Damage

Movement Speed

These should all be configurable.

---

# Lobby Settings

If a gameplay rule may reasonably become a host option in the future:

Do NOT hardcode it.

Examples:

Friendly Fire

Melee Kills

Starting Health

Shield Count

Reload Speed

Round Timer

Weapon Spawn Count

Always design systems to support lobby customization.

---

# Readability

Prefer:

Clear code

Over

Short code.

Good variable names.

Good function names.

Small functions.

Avoid deeply nested code whenever possible.

---

# Naming

Use descriptive names.

Good

RoundManager

WeaponSpawner

VictoryPresentation

PlayerInventory

PowerupData

Avoid

Manager2

Thing

Data

Handler

Script

Temp

---

# Functions

Functions should do one thing.

Avoid functions that are hundreds of lines long.

If a function becomes difficult to understand:

Split it into helper functions.

---

# Comments

Only comment code that benefits from explanation.

Do NOT comment obvious code.

Good comments explain WHY.

Not WHAT.

Example

GOOD

Delay allows the victory animation to finish before changing scenes.

BAD

Increase player speed.

speed += 1

---

# Signals

Prefer signals over tightly coupled references.

Reduce dependencies between systems whenever practical.

---

# Scenes

Keep scenes modular.

Examples:

HUD

Pause Menu

Victory Presentation

Main Menu

Lobby

Settings

Each should be independent.

---

# Resources

Store gameplay data inside Resources whenever practical.

Examples:

Weapon Data

Powerup Data

Item Data

Player Cosmetic Data

Avoid hardcoding values across multiple scripts.

---

# Performance

Do not optimize prematurely.

Readable code is preferred unless profiling identifies a performance issue.

Optimize only after measuring.

---

# Error Handling

Avoid silent failures.

Provide helpful error messages.

Use assertions where appropriate.

Validate important references before use.

---

# Debugging

Temporary debug code should be clearly marked.

Remove temporary debugging before considering a feature complete.

Never remove existing debug tools without permission.

---

# Documentation

When a feature is completed:

Update:

docs/TODO.md

docs/ARCHITECTURE.md

if the project structure changed.

---

# Feature Workflow

Every feature should follow this process.

1. Understand request.

2. Explain implementation.

3. Identify affected files.

4. Implement feature.

5. Verify implementation.

6. Report changes.

7. Update documentation if needed.

---

# Gameplay Philosophy

Never change the core identity of One Gun unless explicitly instructed.

Current Core Rules:

• There is only ONE gun.

• One bullet always kills.

• Reload takes approximately 2 seconds.

• Melee disarms the gun holder.

• Gun drops at the point of disarm.

• Melee kills are optional through lobby settings.

• Future features should respect these core mechanics.

---

# Future Expansion

Assume the game will eventually support:

- Cosmetics

- Unlockables

- Additional maps

- New melee weapons

- Seasonal events

- Ranked mode

- Tournament mode

- Statistics

- Achievements

- More lobby settings

Do not design systems that would prevent future expansion.

---

# AI Expectations

Claude should behave like a senior gameplay programmer.

Before implementing:

Think first.

Read only the files necessary.

Reuse existing systems.

Keep code clean.

Avoid unnecessary complexity.

Build systems that are easy to maintain.

When uncertain:

Ask instead of assuming.

---

# Project Goal

Every system should reinforce the fantasy of One Gun:

A fast, competitive, chaotic multiplayer game where every player fights over a single gun.

If a feature does not strengthen that fantasy, reconsider the implementation.


# Claude Session Rules

For every task:

1. Read only the files required.
2. Do not inspect the entire project unless requested.
3. Explain the implementation before coding.
4. Keep changes localized.
5. Reuse existing systems whenever possible.
6. Stop after completing the requested task.
7. Summarize all modified files.
8. Suggest follow-up improvements separately instead of implementing them automatically.