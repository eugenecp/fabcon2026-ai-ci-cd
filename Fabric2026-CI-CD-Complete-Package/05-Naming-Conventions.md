# Naming Conventions for Microsoft Fabric Artifacts

**Version:** 1.0  
**Last Updated:** March 2026  
**Based on:** [Advancing Analytics Naming Guidelines](https://www.advancinganalytics.co.uk/blog/2023/8/16/whats-in-a-name-naming-your-fabric-artifacts)

## Why Naming Conventions Matter

Consistent naming enables:
- **Instant Recognition**: Know what an artifact does from its name
- **Easier Searches**: Find artifacts quickly
- **Better Organization**: Group related items naturally
- **Clear Dependencies**: Understand execution order
- **Team Alignment**: Everyone follows same patterns

## The Naming Structure

```
ArtifactType_Index_Stage_Description_Suffix
```

**Use underscores** to separate each part. Not all parts are required - use according to your needs.

### Example Breakdown

```
NB_2000_SILVER_Transform_Trip_Data
│  │    │      │
│  │    │      └─ Description: What it does
│  │    └──────── Stage: Medallion layer
│  └───────────── Index: Execution order
└──────────────── Type: Notebook
```

## Naming Constraints

**Critical Rules:**
1. **First character must be a letter** (not a number)
2. **Only underscores and alphanumeric characters** (no hyphensno spaces, no special chars)
3. **Apply consistently across all artifact types**

**Why these restrictions?**
- Lakehouses have the strictest naming rules
- Applying lakehouse rules to everything ensures consistency
- Prevents errors when referencing artifacts

## Artifact Type Abbreviations

Use standard abbreviations for easy identification:

| Artifact Type | Abbreviation | Example |
|--------------|--------------|---------|
| **Lakehouse** | LH | `LH_NYC_Taxi` |
| **Notebook** | NB | `NB_2000_SILVER_Transform` |
| **Pipeline** | PL | `PL_1000_BRONZE_Load_Data` |
| **Dataflow** | DFL | `DFL_Extract_Customer_Data` |
| **Spark Job Definition** | SJ | `SJ_Process_Large_Files` |
| **Semantic Model** | SM | `SM_NYC_Taxi_Analytics` |
| **Power BI Dataset** | DS | `DS_Sales_Dashboard` |
| **Datamart** | DM | `DM_Finance_Reporting` |
| **Warehouse** | WH | `WH_Enterprise_Data` |
| **ML Model** | MDL | `MDL_Predict_Churn_RF` |
| **ML Experiment** | EXP | `EXP_Churn_Optimization` |
| **Database** | DB | `DB_Metadata` |
| **Queryset** | QS | `QS_Customer_Insights` |
| **Eventstream** | ES | `ES_IoT_Sensor_Stream` |
| **Variable Library** | VL | `VL_Configuration` |
| **Environment** | ENV | `ENV_Production_Config` |

## Index Numbers (Optional)

Use 4-digit numbers to indicate **ordering** or **medallion layer**:

```
1000 - Bronze layer / First step / Raw data
2000 - Silver layer / Second step / Cleansed data
3000 - Gold layer / Third step / Business aggregates
4000+ - Additional layers or specialized processing
```

**Why 4 digits?**
- Allows adding steps in between without renaming
- Example: Add 1500 between 1000 and 2000 later
- Provides clear grouping by hundreds/thousands

**Examples:**
- `1000` - Initial Bronze ingestion
- `1100` - Bronze reference data load
- `1200` - Bronze API data extraction
- `2000` - Silver transformation
- `2100` - Silver enrichment
- `3000` - Gold aggregation

## Stage Identifiers (Optional)

Include the **target medallion layer** or **data maturity stage**:

### Standard Medallion Architecture

| Stage | Description | Use For |
|-------|-------------|---------|
| **BRONZE** | Raw ingestion layer | Unprocessed data from source |
| **SILVER** | Cleansed and conformed | Validated, standardized data |
| **GOLD** | Business-level | Aggregates, analytics-ready |

### Alternative Stage Names

You can use your own naming convention:

| Alternative | Equivalent | Use Case |
|------------|------------|----------|
| **RAW** | Bronze | Raw data staging |
| **BASE** | Silver | Baseline cleansed data |
| **ENRICHED** | Between Silver/Gold | Enhanced with external data |
| **CURATED** | Gold | Business-ready datasets |
| **SERVING** | Gold | API/report serving layer |

**Choose one system and be consistent!**

## Description Guidelines

The description should **briefly explain the artifact's purpose**:

### For Lakehouses
- **Subject of data**: `NYC_Taxi`, `Sales`, `Customer`
- Keep it simple and recognizable

### For Notebooks
- **Process or transformation**: `Transform_Trip_Data`, `Load_Customer_Info`
- Use action verbs: Transform, Load, Extract, Validate, Enrich

### For Pipelines
- **Action performed**: `Load_Reference_Data`, `Daily_Refresh`
- Describe the orchestration purpose

### For ML Models
- **Use case + algorithm**: `Predict_Churn`, `Forecast_Demand`
- Include algorithm suffix if multiple models

### Best Practices for Descriptions
- ✅ Be specific but concise
- ✅ Use common business terms
- ✅ Avoid abbreviations unless universal
- ❌ Don't include dates or versions (use Git for versioning)
- ❌ Don't use special characters

## Suffix for ML Artifacts (Optional)

For machine learning models, append the **algorithm type**:

| Algorithm | Abbreviation | Example |
|-----------|--------------|---------|
| Decision Tree | DT | `MDL_Predict_Churn_DT` |
| Random Forest | RF | `MDL_Predict_Churn_RF` |
| XGBoost | XGB | `MDL_Predict_Churn_XGB` |
| Light GBM | LGBM | `MDL_Forecast_Sales_LGBM` |
| Logistic Regression | LOR | `MDL_Classify_Risk_LOR` |
| Linear Regression | LIR | `MDL_Estimate_Value_LIR` |
| Support Vector Machines | SVM | `MDL_Classify_Fraud_SVM` |
| K Nearest Neighbours | KNN | `MDL_Recommend_Products_KNN` |
| Neural Network | NN | `MDL_Image_Recognition_NN` |

**Why include algorithm?**
- Enables comparison of different approaches
- Makes model experimentation trackable
- Clear which model version is deployed

## Complete Naming Examples

### Lakehouses

**Multi-Layer Lakehouse** (recommended):
```
LH_NYC_Taxi
```
- Single lakehouse with multiple schemas (bronze, silver, gold, control)
- Simplifies management
- Easier permissions

**Single-Layer Lakehouses**:
```
LH_1000_BRONZE_NYC_Taxi  # Bronze layer only
LH_2000_SILVER_NYC_Taxi  # Silver layer only
LH_3000_GOLD_NYC_Taxi    # Gold layer only
```
- Separate lakehouse per layer
- Use when strict layer isolation needed
- More complex to manage

### Notebooks

```
NB_1000_BRONZE_Download_Taxi_Data
NB_1100_BRONZE_Download_Reference_Data
NB_2000_SILVER_Transform_Trip_Data
NB_2100_SILVER_Enrich_With_Weather
NB_3000_GOLD_Aggregate_Daily_Metrics
NB_3100_GOLD_Calculate_KPIs
```

**Pattern:**
- Index indicates execution order and layer
- Stage shows which lakehouse/layer it targets
- Description explains the specific transformation

### Pipelines

```
PL_1000_BRONZE_Load_All_Sources
PL_1100_BRONZE_Load_Reference_Data
PL_1200_BRONZE_Load_API_Data
PL_2000_SILVER_Transform_From_Bronze
PL_2100_SILVER_Daily_Refresh
PL_3000_GOLD_Transform_From_Silver
PL_3100_GOLD_Build_Analytics_Tables
```

**Pattern:**
- Index shows dependency order
- Stage indicates which layer it operates on
- Description explains orchestration purpose

### Semantic Models

```
SM_NYC_Taxi_Analytics    # For reports and dashboards
SM_Sales_Executive       # For executive reporting
SM_Customer_360          # Customer insights model
```

**Pattern:**
- No index/stage needed (they don't fit medallion architecture)
- Description indicates business purpose
- Keep business-friendly names

### ML Models & Experiments

```
EXP_Trip_Duration_Optimization    # Experiment comparing models
MDL_Predict_Trip_Duration_XGB     # XGBoost production model
MDL_Predict_Trip_Duration_RF      # Random Forest alternative
MDL_Predict_Trip_Duration_NN      # Neural network version
```

**Pattern:**
- Experiment (EXP) for research/training
- Model (MDL) for deployed/production models
- Suffix shows algorithm type

### Variable Libraries & Environments

```
VL_NYC_Taxi           # Variables for NYC Taxi project
VL_Configuration      # Global configuration
ENV_Production        # Production environment config
ENV_Development       # Development environment config
```

**Pattern:**
- Simple, descriptive names
- Indicate scope (project vs. global)

## Special Considerations

### Power BI Reports and Apps

**For business-facing artifacts**, use **business-friendly names WITHOUT technical prefixes**:

❌ **Don't use:**
```
RP_NYC_Taxi_Executive_Dashboard
APP_Sales_Analytics
```

✅ **Do use:**
```
NYC Taxi Executive Dashboard
Sales Analytics
Customer Insights
```

**Why?**
- End users see these names
- Technical prefixes confuse business stakeholders
- Reports and apps are consumption layer

### Default Artifacts

Some artifacts get auto-generated with fixed names:

- **Warehouse/Lakehouse Default Dataset**: Can't be renamed
- **Lakehouse SQL Endpoint**: Can't be renamed
- **Datamart Default Dataset**: Can't be renamed

**Workaround:** Name the parent artifact properly; child artifacts will inherit:
- `LH_NYC_Taxi` → Default Dataset: `LH_NYC_Taxi_DefaultDataset`

## Naming Decision Tree

```
┌─────────────────────────────┐
│    What type of artifact?   │
└──────────────┬──────────────┘
               │
      ┌────────┴─────────┐
      │                  │
  Data Layer         Consumption
      │                  │
      ├─ Lakehouse       ├─ Report (business name)
      ├─ Notebook        ├─ App (business name)
      ├─ Pipeline        └─ Dashboard (business name)
      ├─ Dataflow
      └─ Use full pattern:
         Type_Index_Stage_Description

               │
      Is it multi-layer or single-layer?
               │
      ┌────────┴────────┐
  Multi-layer      Single-layer
      │                 │
  LH_Subject      LH_Index_Stage_Subject
      │                 │
  Use schemas     Use separate lakehouses
  (bronze,        per layer
   silver,
   gold)
```

## Best Practices

### Do's ✅

1. **Be Consistent**
   - Pick a pattern and stick to it
   - Team alignment is more important than perfect naming

2. **Think Long-Term**
   - Names should make sense in 6 months
   - Avoid temporary or trendy names

3. **Use Business Terms**
   - "Customer" not "CUST_TBL"
   - "Sales" not "SLS_FC"

4. **Document Exceptions**
   - If you must break convention, document why
   - Add comment in artifact metadata

5. **Plan Numbering**
   - Leave gaps in index numbers (1000, 2000, 3000)
   - Allows inserting steps later

### Don'ts ❌

1. **Don't Use Special Characters**
   - No hyphens, spaces, parentheses
   - Only underscores and alphanumerics

2. **Don't Include Dates or Versions**
   - Use Git for versioning
   - Dates become stale quickly

3. **Don't Abbreviate Unnecessarily**
   - `Transform` not `Xfrm`
   - `Customer` not `Cust`

4. **Don't Mix Conventions**
   - Pick one system (Bronze/Silver/Gold OR Raw/Base/Curated)
   - Don't switch mid-project

5. **Don't Make Names Too Long**
   - Aim for < 50 characters
   - Be descriptive but concise

## Handling Renames

**Problem:** You need to rename an artifact but it breaks dependencies.

**Solutions:**

1. **For Lakehouses/Notebooks/Pipelines**:
   - Fabric doesn't allow direct rename of most artifacts
   - Must create new artifact with correct name
   - Migrate content
   - Test thoroughly
   - Delete old after validation

2. **For Development**:
   - Fix early in development cycle
   - Before other artifacts depend on it
   - Better to rename now than never

3. **For Production**:
   - Planned maintenance window
   - Update all references
   - Test in lower environments first
   - Document breaking change

## Migration Strategy

**Adopting naming conventions on an existing project:**

### Phase 1: New Artifacts (Weeks 1-2)
- Apply naming convention to all new artifacts
- Document the new standard
- Train team members

### Phase 2: Low-Risk Renames (Weeks 3-4)
- Rename artifacts with no dependencies
- Update documentation
- Test in dev environment

### Phase 3: High-Impact Renames (Weeks 5-8)
- Identify critical artifacts needing rename
- Plan migration with stakeholders
- Schedule maintenance windows
- Update downstream dependencies
- Comprehensive testing

### Phase 4: Complete (Week 9+)
- All artifacts follow new convention
- Old naming patterns deprecated
- Documentation updated
- Training completed

## Quick Reference Card

```
┌─────────────────────────────────────────────────────┐
│         FABRIC ARTIFACT NAMING CHEAT SHEET          │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Pattern: Type_Index_Stage_Description_Suffix       │
│                                                      │
│  Lakehouse:  LH_NYC_Taxi                           │
│  Notebook:   NB_2000_SILVER_Transform_Data         │
│  Pipeline:   PL_1000_BRONZE_Load_Data              │
│  Model:      MDL_Predict_Churn_XGB                 │
│                                                      │
│  Index:      1000 = Bronze                          │
│              2000 = Silver                          │
│              3000 = Gold                            │
│                                                      │
│  Rules:      • Start with letter                    │
│              • Underscores only                     │
│              • No special characters                │
│              • Be consistent!                       │
│                                                      │
└─────────────────────────────────────────────────────┘
```

---

**📝 Print this guide and keep it handy!** Consistent naming is the foundation of a maintainable Fabric workspace.
