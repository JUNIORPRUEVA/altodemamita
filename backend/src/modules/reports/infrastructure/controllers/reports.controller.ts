import { Controller, Get, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { ReportRangeDto } from '../../application/dto/report-range.dto';
import { ReportsService } from '../../application/services/reports.service';

@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('summary')
  @RequirePermissions(PERMISSIONS.reportsRead)
  getSummary() {
    return this.reportsService.getSummary();
  }

  @Get('sales')
  @RequirePermissions(PERMISSIONS.reportsRead)
  getSalesReport(@Query() query: ReportRangeDto) {
    return this.reportsService.getSalesReport(query);
  }

  @Get('payments')
  @RequirePermissions(PERMISSIONS.reportsRead)
  getPaymentsReport(@Query() query: ReportRangeDto) {
    return this.reportsService.getPaymentsReport(query);
  }

  @Get('delinquency')
  @RequirePermissions(PERMISSIONS.reportsRead)
  getDelinquencyReport(@Query() query: ReportRangeDto) {
    return this.reportsService.getDelinquencyReport(query);
  }
}