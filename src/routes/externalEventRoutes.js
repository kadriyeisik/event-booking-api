const express = require("express");
const router = express.Router();

const { getExternalEvents } = require("../controllers/externalEventController");

router.get("/", getExternalEvents);

module.exports = router;