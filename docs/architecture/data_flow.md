# Data Flow

## Overview

The data flow describes how a pipeline run moves through the system from
submission to completion.

## Sequence Diagram

![Data Flow](../../sequence_diagram.png)

## Execution Flow

1. User submits a run from the dashboard.

2. The dashboard sends a request to the backend API:

POST /runs

3. The backend API creates a run record in Firestore:

status = submitted

4. The backend API launches a Cloud Run Job.

5. The Cloud Run Job begins execution and updates Firestore:

status = running

6. The job reads input data and reference resources from Cloud Storage.

7. The pipeline executes inside the container.

8. Outputs, logs, and the HTML report are written to Cloud Storage.

9. The job updates Firestore with the final state:

status = succeeded or failed

10. The dashboard polls the API for run status.

11. The API reads run metadata from Firestore.

12. The API returns run details and artifact links to the dashboard.
