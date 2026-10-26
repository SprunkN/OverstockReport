use MercuryReport

declare @Branch				varchar(50)
declare @CalendarMonthID	int
declare @StartDate			date = '2026-01-01'
declare @EndDate				date = '2026-04-30'
declare @PriorStartDate		date = DATEADD(year, -1, @StartDate)
declare @PriorEndDate		date = DATEADD(year, -1, @EndDate)
declare @CurrentStartMonthID	int
declare @CurrentEndMonthID	int
declare @PriorStartMonthID	int
declare @PriorEndMonthID	int
declare @Branches			varchar(Max)
declare @Areas				varchar(Max)
declare @AreaList			table (Area		varchar(5))
declare @BranchList			table (Branch   varchar(5))

set @Branches	= '1004
714'
--set @Areas		= '02-02'

set @CurrentStartMonthID = (
    select cm.CalendarMonthID
    from CalendarMonth as cm (nolock)
    where @StartDate between cm.MonthBegin and cm.MonthEnd
)

set @CurrentEndMonthID = (
    select cm.CalendarMonthID
    from CalendarMonth as cm (nolock)
    where @EndDate between cm.MonthBegin and cm.MonthEnd
)

set @PriorStartMonthID = (
    select cm.CalendarMonthID
    from CalendarMonth as cm (nolock)
    where @PriorStartDate between cm.MonthBegin and cm.MonthEnd
)

set @PriorEndMonthID = (
    select cm.CalendarMonthID
    from CalendarMonth as cm (nolock)
    where @PriorEndDate between cm.MonthBegin and cm.MonthEnd
)

Insert into @AreaList(Area)			(SELECT Value FROM dbo.[Split](@Areas,		CHAR(13)+CHAR(10)) AS s)
Insert into @BranchList(Branch)		(SELECT Value FROM dbo.[Split](@Branches,	CHAR(13)+CHAR(10)) AS s)
Insert into @BranchList(Branch)		(SELECT DISTINCT BranchNumber FROM Branch_v WHERE AreaNumber in (SELECT * FROm @AreaList))

set @CalendarMonthID = ( select cm.CalendarMonthID
                           from CalendarMonth as cm (nolock) where getdate() between cm.MonthBegin and cm.MonthEnd)


if object_id('tempdb.dbo.#LastID','U') is not null
	drop table #LastID;
create table #LastID(BranchNodeID int, VendorNodeID int, Skuid int, LastDate smalldatetime, Qty int, InvTransDetailId uniqueidentifier)
              insert #LastID(BranchNodeID, VendorNodeID, Skuid, LastDate, Qty,InvTransDetailId)
				  select ith.AdjSupplyChainNodeID, 
						 ith.SourceSupplyChainNodeID, 
						 itd.SkuID,
						 itsd.ReceivedDate, 
						 itsd.QtyReceived,
						 itsd.InvTransDetailID
				 from InvTransHeader ith (nolock)
				join InvTransDetail		as itd (nolock) on itd.InvTransHeaderID = ith.InvTransHeaderID
				join InvTransShipDetail as itsd (nolock) on itsd.InvTransDetailID = itd.InvTransDetailID 
				join SupplyChainNode	as scn (nolock) on scn.SupplyChainNodeID = ith.AdjSupplyChainNodeID 
											and (scn.Number	 in (select * from @BranchList)			
											or (select count(1) where exists (select * from @BranchList))  = 0)
				join SKU as s (nolock) on s.SKUID = itd.SkuID and s.ProductTypeID = 1
              
              where exists
              (
                select ith2.AdjSupplyChainNodeID,
                       itd2.SkuID,                                     
                       max(itsd2.ReceivedDate) as ReceievedDate
                from InvTransHeader ith2 (nolock)
                join InvTransDetail as itd2 (nolock) on itd2.InvTransHeaderID = ith2.InvTransHeaderID
                join InvTransShipDetail as itsd2 (nolock) on itsd2.InvTransDetailID = itd2.InvTransDetailID                    
                join SupplyChainNode as scn (nolock) on scn.SupplyChainNodeID = ith.AdjSupplyChainNodeID
                join SKU as s (nolock) on s.SKUID = itd.SkuID 
				where ith2.AdjSupplyChainNodeID = ith.AdjSupplyChainNodeID
                and itd2.SkuID = itd.SkuID
                and ith2.HeaderClassCodeID = 5
                and s.ProductTypeID = 1
                and (scn.Number	 in (select * from @BranchList)			
						or (select count(1) where exists (select * from @BranchList))  = 0)      
                group by ith2.AdjSupplyChainNodeID, itd2.SkuID         
                having itsd.ReceivedDate = max(itsd2.ReceivedDate));

select
		bhv.AreaNumber,
		bhv.BranchNumber,
        pl.Name as Line,
        s.ItemNumber,
        s.[Description],
        sdr.Code + shr.Code			as [Rank],
        bpcc.ReplacementCost		as RepCost,
        sci.OnHandQty,
        isnull(py.CurrentPeriodSales,0) as [CurrentPeriodSales],
        isnull(py.PriorYearSales,0) as [PriorYearSales],
        isnull(py.CurrentPeriodSales,0) - isnull(py.PriorYearSales,0) as [SalesVsPriorYear],
        isnull(py.CurrentPeriodSales,0) as [Projection],
        case when sci.OnHandQty > isnull(py.CurrentPeriodSales,0)
               then sci.OnHandQty - isnull(py.CurrentPeriodSales,0) end as [OverStock],
        case when sci.OnHandQty > isnull(py.CurrentPeriodSales,0)
               then sci.OnHandQty - isnull(py.CurrentPeriodSales,0) end * bpcc.ReplacementCost as [OverStock$],
        ld.LastDate as [LastRecv],
        scn.Name as [LastVendor]
		 
from SupplyChainInventory as sci (nolock)
join SKU as s (nolock) on s.SkuID = sci.SkuID
join BranchHierarchy_v as bhv (nolock) on bhv.BranchSupplyChainNodeID = sci.SupplyChainNodeID
join ProductLine as pl (nolock) on pl.ProductLineID = s.ProductLineID
join BranchProductCostCalculated as bpcc (nolock) on bpcc.SKUID = s.SKUID and bpcc.SupplyChainNodeID = sci.SupplyChainNodeID
join SupplyChainNodeSkuAssoc as scnsa (nolock) on scnsa.SupplyChainNodeID = bpcc.SupplyChainNodeID and scnsa.SkuID = bpcc.SkuID
join SkuHitRank as shr (nolock) on shr.SkuHitRankID = scnsa.SkuHitRankID
join SkuDollarRank as sdr (nolock) on sdr.SkuDollarRankID = scnsa.SkuDollarRankID
join #LastID ld on ld.BranchNodeID = sci.SupplyChainNodeID and ld.Skuid = sci.SkuID
join SupplyChainNode as scn (nolock) on scn.SupplyChainNodeID = ld.VendorNodeID
left join ( select	scncmss.SkuID,
				sum(case when scncmss.CalendarMonthID between @CurrentStartMonthID and @CurrentEndMonthID
					 then scncmss.QtyNonDirectSales - scncmss.QtyExceptional + scncmss.QtyLost
					 else 0 end) as [CurrentPeriodSales],
				sum(case when scncmss.CalendarMonthID between @PriorStartMonthID and @PriorEndMonthID
					 then scncmss.QtyNonDirectSales - scncmss.QtyExceptional + scncmss.QtyLost
					 else 0 end) as [PriorYearSales]
            from SupplyChainNodeCalendarMonthSkuSales as scncmss (nolock)
            join SupplyChainNode as scn (nolock) on scn.SupplyChainNodeID = scncmss.SupplyChainNodeID
            where (scn.Number	 in (select * from @BranchList)			
					or (select count(1) where exists (select * from @BranchList))  = 0)         
            group by
            scncmss.SkuID) py on py.SKUID = s.SKUID
where sci.OnHandQty > 0
and s.ProductTypeID = 1
and (bhv.BranchNumber	 in (select * from @BranchList)			
	or (select count(1) where exists (select * from @BranchList))  = 0)			
and sci.OnHandQty > isnull(py.CurrentPeriodSales,0)
--and s.ItemNumber = '82011-101' 
ORDER BY AreaNumber, BranchNumber, Line
