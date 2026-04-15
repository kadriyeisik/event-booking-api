const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS
  }
});

const sendExpiredEventEmail = async (event) => {
  const mailOptions = {
    from: process.env.EMAIL_USER,
    to: process.env.ADMIN_EMAIL,
    subject: `Expired Event Updated: ${event.title}`,
    text: `
The following event has been automatically updated to inactive.

Event ID: ${event.id}
Title: ${event.title}
Location: ${event.location}
Event Date: ${event.event_date}
Status: inactive
    `
  };

  await transporter.sendMail(mailOptions);
};
const sendReminderEmail = async (booking, event) => {
  const mailOptions = {
    from: process.env.EMAIL_USER,
    to: booking.customer_email,
    subject: `Reminder: Your event is tomorrow - ${event.title}`,
    text: `
Hello ${booking.customer_name},

This is a reminder that your booked event is tomorrow.

Event: ${event.title}
Location: ${event.location}
Date: ${event.event_date}
Tickets: ${booking.ticket_count}

See you there!
    `
  };

  await transporter.sendMail(mailOptions);
};

const sendPasswordResetEmail = async (toEmail, resetToken) => {
  const resetLink = `myapp://reset-password?token=${resetToken}`;

  const mailOptions = {
    from: process.env.EMAIL_USER,
    to: toEmail,
    subject: "Şifre Sıfırlama Talebi",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #6200EE;">Şifre Sıfırlama</h2>
        <p>Şifrenizi sıfırlamak için aşağıdaki kodu uygulamaya girin:</p>
        <div style="background: #f4f4f4; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0;">
          <h1 style="color: #6200EE; letter-spacing: 8px; font-size: 36px; margin: 0;">${resetToken}</h1>
        </div>
        <p style="color: #666;">Bu kod <strong>15 dakika</strong> geçerlidir.</p>
        <p style="color: #999; font-size: 12px;">Eğer bu talebi siz yapmadıysanız bu emaili görmezden gelebilirsiniz.</p>
      </div>
    `
  };

  await transporter.sendMail(mailOptions);
};

module.exports = { sendExpiredEventEmail, sendReminderEmail, sendPasswordResetEmail };