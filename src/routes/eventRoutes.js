const { verifyToken, requireAdmin } = require("../middlewares/authMiddleware");
const express = require("express");
const router = express.Router();

const {
  getAllEvents,
  getEventById,
  createEvent,
  updateEvent,
  deleteEvent,
  bookEvent,
  getMyBookings,
  getEventChatMessages,
  getEventChatUnreadCounts,
  markEventChatAsRead,
  getAllBookings,
  updateBookingStatus,
  getAllEventsCombined
} = require("../controllers/eventController");

router.get("/", getAllEvents);
router.get("/all", getAllEventsCombined);
router.get("/my-bookings", verifyToken, getMyBookings);
router.get("/chat-unread-counts", verifyToken, getEventChatUnreadCounts);
router.get("/:id/chat-messages", verifyToken, getEventChatMessages);
router.post("/:id/chat-read", verifyToken, markEventChatAsRead);
router.get("/bookings", verifyToken, requireAdmin, getAllBookings);
router.patch("/bookings/:bookingId/status", verifyToken, requireAdmin, updateBookingStatus);
router.get("/:id", getEventById);


router.post("/", verifyToken, requireAdmin, createEvent);
router.put("/:id", verifyToken, requireAdmin, updateEvent);
router.delete("/:id", verifyToken, requireAdmin, deleteEvent);
router.patch("/:id", verifyToken, requireAdmin, updateEvent);
router.post("/:id/book", bookEvent);

module.exports = router;