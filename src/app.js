const express = require("express");
const cors = require("cors");
require("dotenv").config();

if (process.env.DISABLE_CRON !== "true") {
  require("./cronJobs");
}

const db = require("./config/db");
const eventRoutes = require("./routes/eventRoutes");
const authRoutes = require("./routes/authRoutes");
const externalEventRoutes = require("./routes/externalEventRoutes");

const app = express();

app.use(cors());
app.use(express.json());
app.use("/external-events", externalEventRoutes);

app.get("/", (req, res) => {
  res.json({
    message: "Event Booking API is running"
  });
});

app.use("/events", eventRoutes);
app.use("/auth", authRoutes);

db.query("SELECT 1", (err) => {
  if (err) {
    console.error("Database connection failed:", err.message);
  } else {
    console.log("Database connected successfully!");
  }
});

module.exports = app;