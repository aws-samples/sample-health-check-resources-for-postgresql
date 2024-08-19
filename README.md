## Sample Health-Check Resources for PostgreSQL

## Purpose

This code repository and the resources within it are meant to assist anyone who is attempting to determine the overall health of their PostgreSQL database. While there are some references to RDS Postgres and Amazon Aurora PostgreSQL-Compatible Edition, this document applies generally to any modern PostgreSQL release with a major version o
f v12+. Contained within this repository is a "PostgreSQL Health Check" BASH script,
which can be run against a database endpoint to generate a report using four queries
to estimate database health. There are also SQL scripts, which are also embedded into
 the BASH script, though they are useful to run on their own if you only need to run
a component of this health-check (or would like to add these queries to your own monitoring automations). Finally, there is a PDF file detailing all of the above resources, with additional resources and context behind why these resources are being used and how they can be measured.

## PostgreSQL Health Check (PDF Document)

This PDF document contains information on how to use all of the resources in this repository, and also contains explanations of the included queries and why they are used. There is additional context on how to enable auto_explain for problimatic queries and how to generate explain plans (useful for troubleshooting problimatic queries and visualizing them)

## Health Check Script (BASH)

This BASH script automates the contents of the PDF file included in this repository, and prints the output into a text format that is consistent and easy to read.

## SQL Scripts

The SQL files included are also embedded into the BASH file (also included), though I thought it would be helpful to include them in a more reusable form.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

