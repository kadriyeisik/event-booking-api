const db = require("../config/db");
const { getIO } = require("../socket");

db.query(
  `
    CREATE TABLE IF NOT EXISTS bookings (
      id INT AUTO_INCREMENT PRIMARY KEY,
      event_id INT NOT NULL,
      customer_name VARCHAR(255) NOT NULL,
      customer_email VARCHAR(255) NOT NULL,
      ticket_count INT NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'pending',
      reminder_sent TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `,
  (err) => {
    if (err) {
      console.error("Failed to ensure bookings table exists:", err.message);
    }
  }
);

db.query(
  `
    CREATE TABLE IF NOT EXISTS chat_messages (
      id INT AUTO_INCREMENT PRIMARY KEY,
      event_id INT NOT NULL,
      sender_email VARCHAR(255) NOT NULL,
      sender_name VARCHAR(255) NOT NULL,
      message TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_chat_event_created (event_id, created_at),
      INDEX idx_chat_sender (sender_email)
    )
  `,
  (err) => {
    if (err) {
      console.error("Failed to ensure chat_messages table exists:", err.message);
    }
  }
);

db.query(
  `
    CREATE TABLE IF NOT EXISTS chat_room_reads (
      id INT AUTO_INCREMENT PRIMARY KEY,
      event_id INT NOT NULL,
      user_email VARCHAR(255) NOT NULL,
      last_read_message_id INT NOT NULL DEFAULT 0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_chat_room_read (event_id, user_email),
      INDEX idx_chat_room_read_user (user_email)
    )
  `,
  (err) => {
    if (err) {
      console.error("Failed to ensure chat_room_reads table exists:", err.message);
    }
  }
);

const canAccessEventChat = ({ eventId, user }, callback) => {
  if (!Number.isInteger(eventId) || eventId <= 0) {
    return callback(new Error("Invalid event id"));
  }

  if (!user?.email) {
    return callback(new Error("User email missing"));
  }

  if (user?.role === "admin") {
    return callback(null, true);
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

db.query(
  `
    SELECT COUNT(*) AS count
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'bookings'
      AND COLUMN_NAME = 'status'
  `,
  (checkErr, rows) => {
    if (checkErr) {
      console.error("Failed to verify bookings.status column:", checkErr.message);
      return;
    }

    if (rows?.[0]?.count > 0) {
      return;
    }

    db.query(
      "ALTER TABLE bookings ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending'",
      (alterErr) => {
        if (alterErr) {
          console.error("Failed to add bookings.status column:", alterErr.message);
        }
      }
    );
  }
);

// GET /events
const getAllEvents = (req, res) => {
  db.query("SELECT * FROM events", (err, results) => {
    if (err) {
      return res.status(500).json({
        message: "Failed to fetch events",
        error: err.message
      });
    }

    res.json({
      message: "Events fetched successfully",
      data: results
    });
  });
};

// GET /events/:id
const getEventById = (req, res) => {
  const id = req.params.id;

  if (isNaN(id)) {
    return res.status(400).json({
      message: "Invalid event id"
    });
  }

  const sql = "SELECT * FROM events WHERE id = ?";

  db.query(sql, [id], (err, results) => {
    if (err) {
      return res.status(500).json({
        message: "Database error",
        error: err.message
      });
    }

    if (results.length === 0) {
      return res.status(404).json({
        message: "Event not found"
      });
    }

    res.json({
      message: "Event fetched successfully",
      data: results[0]
    });
  });
};

// POST /events
const createEvent = (req, res) => {
  const {
    title,
    description,
    category,
    location,
    price,
    capacity,
    status,
    event_date
  } = req.body;

  if (!title || !location || !event_date || capacity === undefined || price === undefined) {
    return res.status(400).json({
      message: "Title, location, event_date, price and capacity are required"
    });
  }

  if (capacity < 0 || price < 0) {
    return res.status(400).json({
      message: "Price and capacity cannot be negative"
    });
  }

  const allowedStatuses = ["active", "inactive", "cancelled"];
  if (status && !allowedStatuses.includes(status)) {
    return res.status(400).json({
      message: "Invalid status value"
    });
  }

  const available_seats = capacity;

  const sql = `
    INSERT INTO events
    (title, description, category, location, price, capacity, available_seats, status, event_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  db.query(
    sql,
    [
      title,
      description,
      category,
      location,
      price,
      capacity,
      available_seats,
      status || "active",
      event_date
    ],
    (err, result) => {
      if (err) {
        return res.status(500).json({
          message: "Failed to create event",
          error: err.message
        });
      }

      res.status(201).json({
        message: "Event created successfully",
        eventId: result.insertId
      });
    }
  );
};
// POST /events/:id/book
const bookEvent = (req, res) => {
  const eventId = req.params.id;

  const { customer_name, customer_email, ticket_count } = req.body;

  // validation
  if (!customer_name || !customer_email || !ticket_count) {
    return res.status(400).json({
      message: "All fields are required"
    });
  }

  if (ticket_count <= 0) {
    return res.status(400).json({
      message: "Ticket count must be greater than 0"
    });
  }

  // 1. Event kontrol
  db.query("SELECT * FROM events WHERE id = ?", [eventId], (err, results) => {
    if (err) {
      return res.status(500).json({
        message: "Database error",
        error: err.message
      });
    }

    if (results.length === 0) {
      return res.status(404).json({
        message: "Event not found"
      });
    }

    const event = results[0];

    // 2. Koltuk kontrol
    if (event.available_seats < ticket_count) {
      return res.status(400).json({
        message: "Not enough seats available"
      });
    }

    // 3. Booking ekle
    const insertSql = `
      INSERT INTO bookings (event_id, customer_name, customer_email, ticket_count, status)
      VALUES (?, ?, ?, ?, 'pending')
    `;

    db.query(
      insertSql,
      [eventId, customer_name, customer_email, ticket_count],
      (err) => {
        if (err) {
          return res.status(500).json({
            message: "Failed to create booking",
            error: err.message
          });
        }

        // 4. Başarı: koltuk düşümü admin onayında yapılır.
        res.status(201).json({
          message: "Booking submitted for approval"
        });
      }
    );
  });
};

// GET /events/bookings
const getAllBookings = (req, res) => {
  const sql = `
    SELECT
      b.id,
      b.event_id,
      b.customer_name,
      b.customer_email,
      b.ticket_count,
      b.status,
      b.created_at,
      e.title,
      e.location,
      e.event_date,
      e.price
    FROM bookings b
    JOIN events e ON b.event_id = e.id
    ORDER BY b.id DESC
  `;

  db.query(sql, (err, results) => {
    if (err) {
      return res.status(500).json({
        message: "Failed to fetch bookings",
        error: err.message
      });
    }

    return res.json({
      message: "Bookings fetched successfully",
      data: results
    });
  });
};

// PATCH /events/bookings/:bookingId/status
const updateBookingStatus = (req, res) => {
  const bookingId = Number(req.params.bookingId);
  const nextStatus = req.body?.status;

  if (!Number.isInteger(bookingId) || bookingId <= 0) {
    return res.status(400).json({ message: "Invalid booking id" });
  }

  if (nextStatus !== "approved" && nextStatus !== "cancelled") {
    return res.status(400).json({ message: "Status must be approved or cancelled" });
  }

  db.query(
    `
      SELECT id, event_id, customer_email, ticket_count, status
      FROM bookings
      WHERE id = ?
      LIMIT 1
    `,
    [bookingId],
    (findErr, rows) => {
      if (findErr) {
        return res.status(500).json({ message: "Database error", error: findErr.message });
      }

      if (!rows.length) {
        return res.status(404).json({ message: "Booking not found" });
      }

      const booking = rows[0];

      if (booking.status === nextStatus) {
        return res.json({ message: "Booking status already updated" });
      }

      const setStatus = () => {
        db.query(
          "UPDATE bookings SET status = ? WHERE id = ?",
          [nextStatus, bookingId],
          (updateErr) => {
            if (updateErr) {
              return res.status(500).json({ message: "Failed to update booking status", error: updateErr.message });
            }

            try {
              const io = getIO();
              console.log("Emitting booking-status-updated to:", booking.customer_email, nextStatus);
              io.to(booking.customer_email).emit("booking-status-updated", {
                bookingId,
                status: nextStatus,
                eventId: booking.event_id
              });
            } catch {
              // Socket server may be unavailable in tests or non-server contexts.
            }

            return res.json({
              message: "Booking status updated",
              data: { id: bookingId, status: nextStatus }
            });
          }
        );
      };

      if (booking.status === "approved" && nextStatus === "cancelled") {
        return db.query(
          "UPDATE events SET available_seats = available_seats + ? WHERE id = ?",
          [booking.ticket_count, booking.event_id],
          (seatErr) => {
            if (seatErr) {
              return res.status(500).json({ message: "Failed to release seats", error: seatErr.message });
            }
            return setStatus();
          }
        );
      }

      if (
        (booking.status === "cancelled" || booking.status === "pending") &&
        nextStatus === "approved"
      ) {
        return db.query(
          "SELECT available_seats FROM events WHERE id = ? LIMIT 1",
          [booking.event_id],
          (eventErr, eventRows) => {
            if (eventErr) {
              return res.status(500).json({ message: "Database error", error: eventErr.message });
            }

            if (!eventRows.length) {
              return res.status(404).json({ message: "Event not found" });
            }

            if (eventRows[0].available_seats < booking.ticket_count) {
              return res.status(400).json({ message: "Not enough seats to approve this booking" });
            }

            db.query(
              "UPDATE events SET available_seats = available_seats - ? WHERE id = ?",
              [booking.ticket_count, booking.event_id],
              (seatErr) => {
                if (seatErr) {
                  return res.status(500).json({ message: "Failed to reserve seats", error: seatErr.message });
                }

                return setStatus();
              }
            );
          }
        );
      }

      return setStatus();
    }
  );
};

// GET /events/my-bookings
const getMyBookings = (req, res) => {
  const userEmail = req.user?.email;
  const userRole = req.user?.role;

  if (!userEmail) {
    return res.status(400).json({
      message: "User email not found in token"
    });
  }

  const isAdmin = userRole === "admin";

  const sql = `
    SELECT
      b.id,
      b.event_id,
      b.customer_name,
      b.customer_email,
      b.ticket_count,
      b.status,
      e.title,
      e.location,
      e.event_date,
      e.price,
      e.status AS event_status
    FROM bookings b
    JOIN events e ON b.event_id = e.id
    WHERE (? = 1 OR b.customer_email = ?)
    ORDER BY b.id DESC
  `;

  db.query(sql, [isAdmin ? 1 : 0, userEmail], (err, results) => {
    if (err) {
      return res.status(500).json({
        message: "Failed to fetch bookings",
        error: err.message
      });
    }

    return res.json({
      message: "Bookings fetched successfully",
      data: results
    });
  });
};

// GET /events/:id/chat-messages
const getEventChatMessages = (req, res) => {
  const eventId = Number(req.params.id);
  const user = req.user;
  const rawLimit = Number(req.query.limit);
  const limit = Number.isInteger(rawLimit)
    ? Math.min(Math.max(rawLimit, 1), 100)
    : 30;
  const rawBeforeId = Number(req.query.beforeId);
  const hasBeforeId = Number.isInteger(rawBeforeId) && rawBeforeId > 0;
  const beforeId = hasBeforeId ? rawBeforeId : 0;

  canAccessEventChat({ eventId, user }, (accessErr, allowed) => {
    if (accessErr) {
      return res.status(400).json({ message: accessErr.message });
    }

    if (!allowed) {
      return res.status(403).json({ message: "You are not allowed to access this event chat" });
    }

    db.query(
      `
        SELECT id, event_id, sender_email, sender_name, message, created_at
        FROM chat_messages
        WHERE event_id = ?
          AND (? = 0 OR id < ?)
        ORDER BY id DESC
        LIMIT ?
      `,
      [eventId, hasBeforeId ? 1 : 0, beforeId, limit + 1],
      (err, rows) => {
        if (err) {
          return res.status(500).json({ message: "Failed to fetch chat messages", error: err.message });
        }

        const hasMore = rows.length > limit;
        const sliced = hasMore ? rows.slice(0, limit) : rows;
        const data = sliced.reverse();
        const nextBeforeId = data.length > 0 ? data[0].id : null;

        return res.json({
          message: "Chat messages fetched successfully",
          data,
          meta: {
            hasMore,
            nextBeforeId,
            limit
          }
        });
      }
    );
  });
};

// GET /events/chat-unread-counts
const getEventChatUnreadCounts = (req, res) => {
  const userEmail = req.user?.email;
  const userRole = req.user?.role;

  if (!userEmail) {
    return res.status(400).json({ message: "User email not found in token" });
  }

  const onRows = (err, rows) => {
    if (err) {
      return res.status(500).json({ message: "Failed to fetch unread chat counts", error: err.message });
    }

    const data = rows.map((row) => ({
      eventId: Number(row.event_id),
      unreadCount: Number(row.unread_count)
    }));

    return res.json({
      message: "Unread chat counts fetched successfully",
      data
    });
  };

  if (userRole === "admin") {
    db.query(
      `
        SELECT cm.event_id, COUNT(*) AS unread_count
        FROM chat_messages cm
        LEFT JOIN chat_room_reads rr
          ON rr.event_id = cm.event_id AND rr.user_email = ?
        WHERE cm.id > COALESCE(rr.last_read_message_id, 0)
        GROUP BY cm.event_id
        HAVING unread_count > 0
      `,
      [userEmail],
      onRows
    );
    return;
  }

  db.query(
    `
      SELECT cm.event_id, COUNT(*) AS unread_count
      FROM chat_messages cm
      JOIN (
        SELECT DISTINCT event_id
        FROM bookings
        WHERE customer_email = ? AND status = 'approved'
      ) allowed ON allowed.event_id = cm.event_id
      LEFT JOIN chat_room_reads rr
        ON rr.event_id = cm.event_id AND rr.user_email = ?
      WHERE cm.id > COALESCE(rr.last_read_message_id, 0)
      GROUP BY cm.event_id
      HAVING unread_count > 0
    `,
    [userEmail, userEmail],
    onRows
  );
  return;
};

// POST /events/:id/chat-read
const markEventChatAsRead = (req, res) => {
  const eventId = Number(req.params.id);
  const user = req.user;
  const userEmail = user?.email;

  if (!userEmail) {
    return res.status(400).json({ message: "User email not found in token" });
  }

  canAccessEventChat({ eventId, user }, (accessErr, allowed) => {
    if (accessErr) {
      return res.status(400).json({ message: accessErr.message });
    }

    if (!allowed) {
      return res.status(403).json({ message: "You are not allowed to access this event chat" });
    }

    db.query(
      `
        SELECT id
        FROM chat_messages
        WHERE event_id = ?
        ORDER BY id DESC
        LIMIT 1
      `,
      [eventId],
      (findErr, rows) => {
        if (findErr) {
          return res.status(500).json({ message: "Failed to mark chat as read", error: findErr.message });
        }

        const latestMessageId = rows?.[0]?.id ? Number(rows[0].id) : 0;

        db.query(
          `
            INSERT INTO chat_room_reads (event_id, user_email, last_read_message_id)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
              last_read_message_id = VALUES(last_read_message_id),
              updated_at = CURRENT_TIMESTAMP
          `,
          [eventId, userEmail, latestMessageId],
          (upsertErr) => {
            if (upsertErr) {
              return res.status(500).json({ message: "Failed to mark chat as read", error: upsertErr.message });
            }

            try {
              const io = getIO();
              io.to(userEmail).emit("chat-unread-reset", {
                eventId,
                unreadCount: 0
              });
            } catch {
              // Socket server may be unavailable in tests or non-server contexts.
            }

            return res.json({
              message: "Chat marked as read",
              data: {
                eventId,
                lastReadMessageId: latestMessageId
              }
            });
          }
        );
      }
    );
  });
};

// PUT /events/:id
const updateEvent = (req, res) => {
  const id = req.params.id;

  if (isNaN(id)) {
    return res.status(400).json({
      message: "Invalid event id"
    });
  }

  const {
    title,
    description,
    category,
    location,
    price,
    capacity,
    status,
    event_date
  } = req.body;

  if (!title || !location || !event_date || capacity === undefined || price === undefined) {
    return res.status(400).json({
      message: "Title, location, event_date, price and capacity are required"
    });
  }

  if (capacity < 0 || price < 0) {
    return res.status(400).json({
      message: "Price and capacity cannot be negative"
    });
  }

  const allowedStatuses = ["active", "inactive", "cancelled"];
  if (status && !allowedStatuses.includes(status)) {
    return res.status(400).json({
      message: "Invalid status value"
    });
  }

  const sql = `
    UPDATE events
    SET title = ?, description = ?, category = ?, location = ?, price = ?, capacity = ?, available_seats = ?, status = ?, event_date = ?
    WHERE id = ?
  `;

  db.query(
    sql,
    [title, description, category, location, price, capacity, capacity, status || "active", event_date, id],
    (err, result) => {
      if (err) {
        return res.status(500).json({
          message: "Failed to update event",
          error: err.message
        });
      }

      if (result.affectedRows === 0) {
        return res.status(404).json({
          message: "Event not found"
        });
      }

      res.json({
        message: "Event updated successfully"
      });
    }
  );
};

// DELETE /events/:id
const deleteEvent = (req, res) => {
  const id = req.params.id;

  if (isNaN(id)) {
    return res.status(400).json({
      message: "Invalid event id"
    });
  }

  const sql = "DELETE FROM events WHERE id = ?";

  db.query(sql, [id], (err, result) => {
    if (err) {
      return res.status(500).json({
        message: "Database error",
        error: err.message
      });
    }

    if (result.affectedRows === 0) {
      return res.status(404).json({
        message: "Event not found"
      });
    }

    res.json({
      message: "Event deleted successfully"
    });
  });
};
const { searchEvents } = require("../providers/ticketmasterService");

const getAllEventsCombined = async (req, res) => {
  try {
    // 1. Local events
    db.query("SELECT * FROM events", async (err, localEvents) => {
      if (err) {
        return res.status(500).json({
          message: "Failed to fetch local events",
          error: err.message
        });
      }

      // 2. External events
      const externalData = await searchEvents({
        keyword: req.query.keyword,
        city: req.query.city,
        countryCode: req.query.countryCode
      });

      const externalEvents = externalData.events;

      // 3. Birleştir
      const combined = [
        ...localEvents.map(e => ({ ...e, source: "local" })),
        ...externalEvents
      ];

      res.json({
        message: "All events (local + external)",
        total: combined.length,
        events: combined
      });
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to combine events",
      error: error.message
    });
  }
};

module.exports = {
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
};