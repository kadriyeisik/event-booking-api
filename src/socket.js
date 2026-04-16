const { Server } = require("socket.io");
const jwt = require("jsonwebtoken");
const db = require("./config/db");

let io;

const getEventRoomName = (eventId) => `event-${eventId}`;
const ADMIN_EMAIL = "admin@test.com";

const sanitizeMessage = (rawMessage) => {
    if (typeof rawMessage !== "string") {
        return "";
    }

    return rawMessage.trim().replace(/\s+/g, " ").slice(0, 1000);
};

const canJoinEventRoom = ({ eventId, user }, callback) => {
    if (!Number.isInteger(eventId) || eventId <= 0) {
        return callback(new Error("Invalid event id"));
    }

    if (user?.role === "admin") {
        return callback(null, true);
    }

    if (!user?.email) {
        return callback(new Error("User email missing"));
    }

    db.query(
        `
            SELECT id
            FROM bookings
            WHERE event_id = ? AND customer_email = ? AND status = 'approved'
            LIMIT 1
        `,
        [eventId, user.email],
        (err, rows) => {
            if (err) {
                return callback(err);
            }

            return callback(null, rows.length > 0);
        }
    );
};

const emitChatNotificationToRecipients = ({ eventId, senderEmail, senderName, message, createdAt }) => {
    const preview = message.length > 120 ? `${message.slice(0, 117)}...` : message;

    db.query(
        `
            SELECT DISTINCT b.customer_email AS email, e.title AS event_title
            FROM bookings b
            LEFT JOIN events e ON e.id = b.event_id
            WHERE b.event_id = ? AND b.status = 'approved'
        `,
        [eventId],
        (err, rows) => {
            if (err) {
                console.error("Failed to resolve chat notification recipients:", err.message);
                return;
            }

            const recipients = new Set(
                rows
                    .map((item) => String(item.email || "").trim().toLowerCase())
                    .filter(Boolean)
            );

            recipients.add(ADMIN_EMAIL);
            recipients.delete(senderEmail);

            const eventTitle = String(rows?.[0]?.event_title || "Etkinlik sohbeti").trim() || "Etkinlik sohbeti";

            const payload = {
                eventId,
                eventTitle,
                senderEmail,
                senderName,
                messagePreview: preview,
                createdAt,
            };

            for (const recipientEmail of recipients) {
                io.to(recipientEmail).emit("chat-notification", payload);
                io.to(recipientEmail).emit("chat-unread-updated", {
                    eventId,
                    unreadDelta: 1,
                });
            }
        }
    );
};

const initSocket = (httpServer) => {
    io = new Server(httpServer, {
        cors: {
            origin: "*",
            methods: ["GET", "POST", "PATCH", "PUT", "DELETE"],
        },
    });

    io.use((socket, next) => {
        const token = socket.handshake.auth?.token;
        if (!token) {
            console.log("Socket auth rejected: token missing");
            return next(new Error("Unauthorized: token missing"));
        }

        jwt.verify(token, process.env.JWT_SECRET || "secretkey123", (err, decoded) => {
            if (err) {
                console.log("Socket auth rejected: invalid token");
                return next(new Error("Unauthorized: invalid token"));
            }

            socket.user = decoded;
            next();
    });
    });

    io.on("connection", (socket) => {
        console.log("Socket connected:", socket.id, "user:", socket.user?.email);

        socket.on("join-room", (email) => {
            if (!email) {
                return;
            }

            socket.join(email);
            console.log("Joined room:", email);
        });

        socket.on("join-event-room", (rawEventId, ack) => {
            const eventId = Number(rawEventId);

            canJoinEventRoom({ eventId, user: socket.user }, (err, allowed) => {
                if (err) {
                    const message = "Failed to validate event room access";
                    console.error(message + ":", err.message);
                    if (typeof ack === "function") {
                        ack({ ok: false, message });
                    }
                    return;
                }

                if (!allowed) {
                    const message = "You are not allowed to join this event room";
                    console.log("Event room join denied:", socket.user?.email, eventId);
                    if (typeof ack === "function") {
                        ack({ ok: false, message });
                    }
                    return;
                }

                const room = getEventRoomName(eventId);
                socket.join(room);
                console.log("Joined event room:", room, "user:", socket.user?.email);
                if (typeof ack === "function") {
                    ack({ ok: true, room });
                }
            });
        });

        socket.on("leave-event-room", (rawEventId, ack) => {
            const eventId = Number(rawEventId);
            if (!Number.isInteger(eventId) || eventId <= 0) {
                if (typeof ack === "function") {
                    ack({ ok: false, message: "Invalid event id" });
                }
                return;
            }

            const room = getEventRoomName(eventId);
            socket.leave(room);
            console.log("Left event room:", room, "user:", socket.user?.email);
            if (typeof ack === "function") {
                ack({ ok: true, room });
            }
        });

        socket.on("event-typing", (payload) => {
            const eventId = Number(payload?.eventId);
            const isTyping = payload?.isTyping === true;

            if (!Number.isInteger(eventId) || eventId <= 0) {
                return;
            }

            canJoinEventRoom({ eventId, user: socket.user }, (err, allowed) => {
                if (err || !allowed) {
                    return;
                }

                const room = getEventRoomName(eventId);
                socket.to(room).emit("event-typing", {
                    eventId,
                    senderEmail: String(socket.user?.email || "").trim().toLowerCase(),
                    senderName: String(socket.user?.name || "User").trim().slice(0, 255),
                    isTyping,
                });
            });
        });

        socket.on("send-event-message", (payload, ack) => {
            const eventId = Number(payload?.eventId);
            const message = sanitizeMessage(payload?.message);

            if (!Number.isInteger(eventId) || eventId <= 0) {
                if (typeof ack === "function") {
                    ack({ ok: false, message: "Invalid event id" });
                }
                return;
            }

            if (!message) {
                if (typeof ack === "function") {
                    ack({ ok: false, message: "Message cannot be empty" });
                }
                return;
            }

            canJoinEventRoom({ eventId, user: socket.user }, (err, allowed) => {
                if (err) {
                    if (typeof ack === "function") {
                        ack({ ok: false, message: "Failed to validate room access" });
                    }
                    return;
                }

                if (!allowed) {
                    if (typeof ack === "function") {
                        ack({ ok: false, message: "You are not allowed to send messages to this room" });
                    }
                    return;
                }

                const senderEmail = String(socket.user?.email || "").trim().toLowerCase();
                const senderName = String(socket.user?.name || senderEmail || "User").trim().slice(0, 255);

                db.query(
                    `
                        INSERT INTO chat_messages (event_id, sender_email, sender_name, message)
                        VALUES (?, ?, ?, ?)
                    `,
                    [eventId, senderEmail, senderName, message],
                    (insertErr, result) => {
                        if (insertErr) {
                            console.error("Failed to store chat message:", insertErr.message);
                            if (typeof ack === "function") {
                                ack({ ok: false, message: "Failed to send message" });
                            }
                            return;
                        }

                        const room = getEventRoomName(eventId);
                        const outgoing = {
                            id: result.insertId,
                            eventId,
                            senderEmail,
                            senderName,
                            message,
                            createdAt: new Date().toISOString(),
                        };

                        io.to(room).emit("event-message", outgoing);
                        emitChatNotificationToRecipients({
                            eventId,
                            senderEmail,
                            senderName,
                            message,
                            createdAt: outgoing.createdAt,
                        });
                        if (typeof ack === "function") {
                            ack({ ok: true, data: outgoing });
                        }
                    }
                );
            });
        });

        socket.on("disconnect", () => {
            console.log("Socket disconnected:", socket.id);
        });
    });

    return io;
};

const getIO = () => {
    if (!io) {
        throw new Error("Socket.io not initialized");
    }

    return io;
};

module.exports = { initSocket, getIO };