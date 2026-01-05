# Claude Status Lines Are the New Terminal Prompt

*And I spent way too long customizing mine.*

---

If you've spent time tweaking your shell prompt or configuring Starship, you know the feeling—there's something nice about having the right information visible when you need it.

Claude Code supports custom status lines, so I put one together for my mobile dev workflow. Here's what I ended up with:

```
⌸ my-app · Opus 4.5 · [████░░░░▒▒] 45% · +127 -34 · $2.15 · feature/auth* · mcp:1
⬢ emulator-5560 · ⬡ emulator-5562
```

I'll walk through each piece and why I find it useful.

## The Icon

The `⌸` is purely decorative. Giving each project its own icon just makes switching between repos feel a little more intentional. It's fun. That's reason enough.

## Directory

I often have multiple Claude instances running across different projects. Seeing which directory Claude is working in helps me stay oriented. The status line shows where Claude was started, and it abbreviates the path when I navigate into subdirectories so it doesn't take up too much space.

## Model

Having the model name visible means I don't have to think about which one I'm using. Small thing, but it removes a bit of mental overhead.

## Context

The `[████░░░░▒▒]` bar shows how much of the context window I've used. Before I had this, I'd work until Claude started forgetting things. Now I can see when I'm getting close to the limit and wrap up more intentionally. It's helped me be more proactive about starting fresh sessions when needed.

## Lines Changed

Seeing `+127 -34` keeps me mindful of my teammates. Someone is going to review this code, and I want to make that experience as smooth as I can.

When I notice the numbers getting larger, it's a good signal to pause and commit what I have. Smaller changes are easier to review and easier to talk through. This little reminder has helped me stay more thoughtful about the code I'm generating before handing it off.

## Cost

I find it helpful to see what a session is costing. It's not about watching every dollar—it's more about staying aware. Some problems need deep exploration, others should be quick. Having the number visible helps me calibrate.

## Branch

Seeing the current branch helps me avoid mistakes. Nothing fancy, just useful to have in view.

## MCP

If you're using MCP servers, `mcp:1` shows they're connected. Helpful for ruling things out when debugging.

## Devices

This is the part that's most specific to mobile dev.

The second line shows my connected emulators and simulators. I can see what's available, which device is currently targeted, and—if I configure it—what version of my app is installed on each one. This makes it easy to ask Claude to target a specific device, and I can verify that builds installed correctly without switching windows.

If you're working on Android or iOS, having visibility into your devices is really helpful.

---

The project is open source: [claude-mobiledev-statusline](https://github.com/himattm/claude-mobiledev-statusline)

Give it a try. If something's missing or broken, open an issue. PRs are welcome.
