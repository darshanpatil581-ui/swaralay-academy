# swaralay-academy
# Swaralay Music Academy

सुगम संगीत व उपशास्त्रीय संगीतावर आधारित

Website for Swaralay Music Academy, Nashik, which teaches Light Vocal Music
and Semi-Classical Music.

## Features
- Public site: Home, About, Courses, Gallery, Announcements, Contact
- Student registration with a manual UPI payment screenshot upload
- Student portal with attendance calendar and 1-hour slot booking
- Admin dashboard: students, payments, batches, attendance, bookings,
  reports, birthday messages and settings
- Responsive layout for desktop, tablet and mobile

## Tech
- Static front end (HTML, CSS, JavaScript), hosted on Vercel
- Supabase for database, login and file storage (schema in `database/schema.sql`)
- WhatsApp Business API for birthday messages, fee reminders and payment confirmations

## Status
The front end currently shows sample data. Login, saving data and WhatsApp
messages are being connected to Supabase.
