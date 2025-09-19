const WebSocket = require("ws");
const repl = require("repl");

const PORT = 3000;

const wss = new WebSocket.Server({ port: PORT }, () => {
  console.log(`Server is running at ws://localhost:${PORT}`);
});

let clients = [];

wss.on("connection", (ws) => {
  console.log("Client connected");
  clients.push(ws);

  ws.on("message", (message) => {
    console.log("Received message", message.toString());
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    });
  });

  ws.on("close", () => {
    console.log("Client disconnected");
    clients = clients.filter((client) => client !== ws);
  });

  ws.on("error", (error) => {
    console.log("WebSocket client error:", error);
  });
});

wss.on("error", (error) => {
  console.log("Error", error);
});

const replServer = repl.start({
  prompt: "💬 Message: ",
  eval: (cmd, context, filename, callback) => {
    const input = cmd.trim();

    // Handle REPL commands
    if (input.startsWith(".")) {
      return callback(null, undefined);
    }

    // Handle exit command
    if (input.toLowerCase() === "exit" || input.toLowerCase() === ".exit") {
      replServer.close();
      return callback(null, undefined);
    }

    // Send simple text as message (not as JavaScript)
    if (
      input &&
      !input.includes("=") &&
      !input.includes("(") &&
      !input.includes("{") &&
      !input.includes("[")
    ) {
      console.log(`📤 Broadcasting: ${input}`);
      clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(input);
        }
      });
      return callback(null, `Message sent: "${input}"`);
    }

    // For JavaScript expressions, evaluate normally
    return callback(null, eval(input));
  },
});

replServer.on("exit", () => {
  console.log("👋 REPL server exited. Shutting down WebSocket server...");
  wss.close(() => {
    console.log("✅ WebSocket server closed");
    process.exit(0);
  });
});
