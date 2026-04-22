const express = require("express");
const router = express.Router();

const {
	createCheckoutSession,
	handleStripeWebhook,
	finalizeCheckoutSession,
	syncMyPaidBookings,
	getMyQrTicket,
	verifyQrTicket
} = require("../controllers/paymentController");
const { verifyToken, requireAdmin } = require("../middlewares/authMiddleware");

router.post("/webhook", handleStripeWebhook);
router.get("/finalize-session", finalizeCheckoutSession);
router.post("/sync-my-payments", verifyToken, syncMyPaidBookings);
router.post("/create-checkout-session", verifyToken, createCheckoutSession);
router.get("/my-qr/:bookingId", verifyToken, getMyQrTicket);
router.post("/verify-qr", verifyToken, requireAdmin, verifyQrTicket);

module.exports = router;