const WebSocket = require("ws");
const readline = require("readline");

const SERVER_URL = "ws://localhost:3000";

// Create WebSocket connection to the server
const ws = new WebSocket(SERVER_URL);

// Create readline interface for user input
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

let isConnected = false;

ws.on("open", () => {
  isConnected = true;
  console.log("✅ Connected to WebSocket server");
  console.log("👂 Listening for messages from server...");
  console.log("💬 You can now send messages! Type and press Enter to send.");
  console.log("🚪 Type 'exit' to disconnect and quit");
  console.log("---");
  promptForMessage();
});

ws.on("message", (data) => {
  const message = data.toString();
  const timestamp = new Date().toLocaleTimeString();
  console.log(`[${timestamp}] 📨 Received: ${message}`);
  if (isConnected) {
    promptForMessage();
  }
});

ws.on("close", () => {
  isConnected = false;
  console.log("❌ Disconnected from WebSocket server");
  rl.close();
});

ws.on("error", (error) => {
  console.error("🚨 WebSocket error:", error.message);
  console.log("💡 Make sure the server is running on port 3000");
  rl.close();
});

function promptForMessage() {
  if (!isConnected) return;

  rl.question("💬 Send message: ", (input) => {
    if (input.trim().toLowerCase() === "exit") {
      console.log("👋 Disconnecting...");
      ws.close();
      return;
    }

    if (input.trim()) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(input);
        console.log(`📤 Sent: ${input}`);
      } else {
        console.log("❌ Cannot send message - not connected to server");
      }
    }

    if (isConnected) {
      promptForMessage();
    }
  });
}

// Handle Ctrl+C gracefully
process.on("SIGINT", () => {
  console.log("\n👋 Closing WebSocket connection...");
  isConnected = false;
  ws.close();
  rl.close();
  process.exit(0);
});
