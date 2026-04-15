const test = require("node:test");
const assert = require("node:assert/strict");
const bcrypt = require("bcryptjs");
const request = require("supertest");

process.env.NODE_ENV = "test";
process.env.DISABLE_CRON = "true";
process.env.JWT_SECRET = "test-secret";

const db = require("../src/config/db");

const state = {
  users: [],
  events: [],
  bookings: [],
  nextUserId: 1,
  nextBookingId: 1
};

const seedState = () => {
  state.users = [];
  state.events = [
    {
      id: 1,
      title: "Tech Conference",
      description: "A big tech event",
      category: "tech",
      location: "Istanbul",
      price: 150,
      capacity: 100,
      available_seats: 100,
      status: "active",
      event_date: "2026-06-13 10:00:00"
    }
  ];
  state.bookings = [];
  state.nextUserId = 1;
  state.nextBookingId = 1;
};

const normalize = (sql) => sql.replace(/\s+/g, " ").trim().toLowerCase();

db.query = (sql, params, callback) => {
  const cb = typeof params === "function" ? params : callback;
  const values = Array.isArray(params) ? params : [];
  const normalized = normalize(sql);

  if (
    normalized.startsWith("create table if not exists users") ||
    normalized.startsWith("create table if not exists password_resets") ||
    normalized.startsWith("create table if not exists bookings") ||
    normalized.startsWith("create table if not exists chat_messages") ||
    normalized.startsWith("alter table bookings add column status") ||
    normalized === "select 1"
  ) {
    return cb?.(null, []);
  }

  if (normalized.includes("from information_schema.columns")) {
    return cb?.(null, [{ count: 1 }]);
  }

  if (normalized.startsWith("select id, name, email, password from users where email = ?")) {
    const user = state.users.find((item) => item.email === values[0]);
    return cb?.(null, user ? [user] : []);
  }

  if (normalized.startsWith("insert into users")) {
    const [name, email, password] = values;
    const newUser = { id: state.nextUserId++, name, email, password };
    state.users.push(newUser);
    return cb?.(null, { insertId: newUser.id, affectedRows: 1 });
  }

  if (normalized === "select * from events") {
    return cb?.(null, state.events);
  }

  if (normalized.startsWith("select * from events where id = ?")) {
    const event = state.events.find((item) => item.id === Number(values[0]));
    return cb?.(null, event ? [event] : []);
  }

  if (normalized.startsWith("update users set")) {
    const userId = values[values.length - 1];
    const user = state.users.find((item) => item.id === userId);
    if (!user) {
      return cb?.(null, { affectedRows: 0 });
    }

    let cursor = 0;
    if (normalized.includes("name = ?")) {
      user.name = values[cursor++];
    }
    if (normalized.includes("password = ?")) {
      user.password = values[cursor++];
    }

    return cb?.(null, { affectedRows: 1 });
  }

  if (normalized.startsWith("insert into bookings (event_id, customer_name, customer_email, ticket_count, status)")) {
    const [eventId, customerName, customerEmail, ticketCount] = values;
    const newBooking = {
      id: state.nextBookingId++,
      event_id: Number(eventId),
      customer_name: customerName,
      customer_email: customerEmail,
      ticket_count: Number(ticketCount),
      status: "pending",
      reminder_sent: 0,
      created_at: "2026-04-11 10:00:00"
    };
    state.bookings.push(newBooking);
    return cb?.(null, { insertId: newBooking.id, affectedRows: 1 });
  }

  if (normalized.startsWith("update events set available_seats = available_seats - ? where id = ?")) {
    const [ticketCount, eventId] = values;
    const event = state.events.find((item) => item.id === Number(eventId));
    event.available_seats -= Number(ticketCount);
    return cb?.(null, { affectedRows: 1 });
  }

  if (normalized.startsWith("update events set available_seats = available_seats + ? where id = ?")) {
    const [ticketCount, eventId] = values;
    const event = state.events.find((item) => item.id === Number(eventId));
    event.available_seats += Number(ticketCount);
    return cb?.(null, { affectedRows: 1 });
  }

  if (normalized.startsWith("select b.id, b.event_id, b.customer_name, b.customer_email, b.ticket_count, b.status, e.title, e.location, e.event_date, e.price, e.status as event_status from bookings b join events e on b.event_id = e.id where b.customer_email = ?")) {
    const results = state.bookings
      .filter((booking) => booking.customer_email === values[0])
      .sort((a, b) => b.id - a.id)
      .map((booking) => {
        const event = state.events.find((item) => item.id === booking.event_id);
        return {
          id: booking.id,
          event_id: booking.event_id,
          customer_name: booking.customer_name,
          customer_email: booking.customer_email,
          ticket_count: booking.ticket_count,
          status: booking.status,
          title: event.title,
          location: event.location,
          event_date: event.event_date,
          price: event.price,
          event_status: event.status
        };
      });
    return cb?.(null, results);
  }

  if (normalized.startsWith("select b.id, b.event_id, b.customer_name, b.customer_email, b.ticket_count, b.status, b.created_at, e.title, e.location, e.event_date, e.price from bookings b join events e on b.event_id = e.id order by b.id desc")) {
    const results = [...state.bookings]
      .sort((a, b) => b.id - a.id)
      .map((booking) => {
        const event = state.events.find((item) => item.id === booking.event_id);
        return {
          id: booking.id,
          event_id: booking.event_id,
          customer_name: booking.customer_name,
          customer_email: booking.customer_email,
          ticket_count: booking.ticket_count,
          status: booking.status,
          created_at: booking.created_at,
          title: event.title,
          location: event.location,
          event_date: event.event_date,
          price: event.price
        };
      });
    return cb?.(null, results);
  }

  if (normalized.startsWith("select id, event_id, customer_email, ticket_count, status from bookings where id = ? limit 1")) {
    const booking = state.bookings.find((item) => item.id === Number(values[0]));
    return cb?.(null, booking ? [booking] : []);
  }

  if (normalized.startsWith("select available_seats from events where id = ? limit 1")) {
    const event = state.events.find((item) => item.id === Number(values[0]));
    return cb?.(null, event ? [{ available_seats: event.available_seats }] : []);
  }

  if (normalized.startsWith("update bookings set status = ? where id = ?")) {
    const [status, bookingId] = values;
    const booking = state.bookings.find((item) => item.id === Number(bookingId));
    booking.status = status;
    return cb?.(null, { affectedRows: 1 });
  }

  return cb?.(new Error(`Unhandled SQL in test stub: ${normalized}`));
};

seedState();

const app = require("../src/app");

test.beforeEach(() => {
  seedState();
});

test("register and login flow works for normal user", async () => {
  const registerResponse = await request(app)
    .post("/auth/register")
    .send({ name: "Test User", email: "user@test.com", password: "123456" });

  assert.equal(registerResponse.status, 201);
  assert.equal(registerResponse.body.user.email, "user@test.com");

  const loginResponse = await request(app)
    .post("/auth/login")
    .send({ email: "user@test.com", password: "123456" });

  assert.equal(loginResponse.status, 200);
  assert.ok(loginResponse.body.token);
  assert.equal(loginResponse.body.user.role, "user");
});

test("profile update changes name and password", async () => {
  await request(app)
    .post("/auth/register")
    .send({ name: "Profile User", email: "profile@test.com", password: "123456" });

  const loginResponse = await request(app)
    .post("/auth/login")
    .send({ email: "profile@test.com", password: "123456" });

  const updateResponse = await request(app)
    .put("/auth/profile")
    .set("Authorization", `Bearer ${loginResponse.body.token}`)
    .send({ name: "Yeni Isim", currentPassword: "123456", newPassword: "654321" });

  assert.equal(updateResponse.status, 200);
  assert.equal(updateResponse.body.user.name, "Yeni Isim");

  const reloginResponse = await request(app)
    .post("/auth/login")
    .send({ email: "profile@test.com", password: "654321" });

  assert.equal(reloginResponse.status, 200);
  assert.equal(reloginResponse.body.user.name, "Yeni Isim");
});

test("booking, my bookings and admin booking management work together", async () => {
  await request(app)
    .post("/auth/register")
    .send({ name: "Booking User", email: "booking@test.com", password: "123456" });

  const userLogin = await request(app)
    .post("/auth/login")
    .send({ email: "booking@test.com", password: "123456" });

  const bookResponse = await request(app)
    .post("/events/1/book")
    .send({ customer_name: "Booking User", customer_email: "booking@test.com", ticket_count: 2 });

  assert.equal(bookResponse.status, 201);
  assert.equal(state.bookings[0].status, "pending");
  assert.equal(state.events[0].available_seats, 100);

  const myBookingsResponse = await request(app)
    .get("/events/my-bookings")
    .set("Authorization", `Bearer ${userLogin.body.token}`);

  assert.equal(myBookingsResponse.status, 200);
  assert.equal(myBookingsResponse.body.data.length, 1);
  assert.equal(myBookingsResponse.body.data[0].ticket_count, 2);

  const adminLogin = await request(app)
    .post("/auth/login")
    .send({ email: "admin@test.com", password: "123456" });

  const adminBookings = await request(app)
    .get("/events/bookings")
    .set("Authorization", `Bearer ${adminLogin.body.token}`);

  assert.equal(adminBookings.status, 200);
  assert.equal(adminBookings.body.data.length, 1);

  const approveResponse = await request(app)
    .patch("/events/bookings/1/status")
    .set("Authorization", `Bearer ${adminLogin.body.token}`)
    .send({ status: "approved" });

  assert.equal(approveResponse.status, 200);
  assert.equal(state.bookings[0].status, "approved");
  assert.equal(state.events[0].available_seats, 98);

  const cancelResponse = await request(app)
    .patch("/events/bookings/1/status")
    .set("Authorization", `Bearer ${adminLogin.body.token}`)
    .send({ status: "cancelled" });

  assert.equal(cancelResponse.status, 200);
  assert.equal(state.bookings[0].status, "cancelled");
  assert.equal(state.events[0].available_seats, 100);
});